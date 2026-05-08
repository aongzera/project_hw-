`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Bilinear Upscaler 2x
//
// This module converts 320x240 source pixels to 640x480 VGA pixels using
// 2x bilinear interpolation.
//
// It does not require reading 4 pixels from the frame buffer at the same time.
// Instead, it reads one source pixel per VGA pixel and uses:
// - prev_pixel for the left neighbor
// - line_buffer for the upper row
//
// VGA 2x2 mapping:
//
// Source pixels:
//   A B
//   C D
//
// VGA output:
//   A              avg(A, B)
//   avg(A, C)      avg(A, B, C, D)
//
// If upscale_enable = 0:
//   The module behaves like normal nearest-neighbor pixel doubling.
//////////////////////////////////////////////////////////////////////////////////

module bilinear_upscaler_2x(
    input wire clk,
    input wire reset,

    input wire active,
    input wire [9:0] vga_x,
    input wire [9:0] vga_y,

    input wire upscale_enable,

    output wire [16:0] read_addr,
    input wire [11:0] read_data,

    output reg [11:0] pixel_out
);

    //============================================================
    // Convert VGA coordinate 640x480 to source coordinate 320x240
    //============================================================

    wire [8:0] src_x = vga_x[9:1];  // 0 to 319
    wire [7:0] src_y = vga_y[8:1];  // 0 to 239

    wire [8:0] src_x_next = (src_x == 9'd319) ? 9'd319 : src_x + 9'd1;
    wire [7:0] src_y_next = (src_y == 8'd239) ? 8'd239 : src_y + 8'd1;

    // If bilinear is enabled:
    //   even x reads current pixel
    //   odd  x reads right pixel
    //   even y reads current row
    //   odd  y reads bottom row
    //
    // If disabled:
    //   always read current source pixel, same as pixel doubling
    wire [8:0] read_x = upscale_enable ?
                        (vga_x[0] ? src_x_next : src_x) :
                        src_x;

    wire [7:0] read_y = upscale_enable ?
                        (vga_y[0] ? src_y_next : src_y) :
                        src_y;

    // read_addr = read_y * 320 + read_x
    // 320 = 256 + 64, so this avoids general multiplication
    wire [16:0] row_base = ({9'b0, read_y} << 8) + ({9'b0, read_y} << 6);

    assign read_addr = active ? (row_base + {8'b0, read_x}) : 17'd0;

    //============================================================
    // Delay metadata by one clock to match synchronous BRAM read
    //============================================================

    reg active_d;
    reg upscale_enable_d;
    reg x_odd_d;
    reg y_odd_d;

    reg [8:0] src_x_d;
    reg [8:0] src_x_next_d;
    reg [8:0] read_x_d;

    //============================================================
    // Line buffer stores one source row: 320 pixels x 12 bits
    //============================================================

    reg [11:0] line_buffer [0:319];

    // Previous pixel in the current scanned row
    reg [11:0] prev_pixel;

    integer i;

    initial begin
        for (i = 0; i < 320; i = i + 1) begin
            line_buffer[i] = 12'h000;
        end
        prev_pixel = 12'h000;
        pixel_out = 12'h000;
    end

    //============================================================
    // Average helper functions
    //============================================================

    function [11:0] avg2;
        input [11:0] p0;
        input [11:0] p1;

        reg [4:0] r;
        reg [4:0] g;
        reg [4:0] b;

        begin
            r = {1'b0, p0[11:8]} + {1'b0, p1[11:8]};
            g = {1'b0, p0[7:4]}  + {1'b0, p1[7:4]};
            b = {1'b0, p0[3:0]}  + {1'b0, p1[3:0]};

            avg2 = {r[4:1], g[4:1], b[4:1]};
        end
    endfunction

    function [11:0] avg4;
        input [11:0] p0;
        input [11:0] p1;
        input [11:0] p2;
        input [11:0] p3;

        reg [5:0] r;
        reg [5:0] g;
        reg [5:0] b;

        begin
            r = {2'b00, p0[11:8]} + {2'b00, p1[11:8]} +
                {2'b00, p2[11:8]} + {2'b00, p3[11:8]};

            g = {2'b00, p0[7:4]} + {2'b00, p1[7:4]} +
                {2'b00, p2[7:4]} + {2'b00, p3[7:4]};

            b = {2'b00, p0[3:0]} + {2'b00, p1[3:0]} +
                {2'b00, p2[3:0]} + {2'b00, p3[3:0]};

            avg4 = {r[5:2], g[5:2], b[5:2]};
        end
    endfunction

    //============================================================
    // Main interpolation logic
    //============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_d <= 1'b0;
            upscale_enable_d <= 1'b0;
            x_odd_d <= 1'b0;
            y_odd_d <= 1'b0;

            src_x_d <= 9'd0;
            src_x_next_d <= 9'd0;
            read_x_d <= 9'd0;

            prev_pixel <= 12'h000;
            pixel_out <= 12'h000;
        end
        else begin
            //====================================================
            // Process read_data from previous cycle
            //====================================================

            if (!active_d) begin
                pixel_out <= 12'h000;
            end
            else if (!upscale_enable_d) begin
                // Nearest-neighbor / pixel doubling mode
                pixel_out <= read_data;
            end
            else begin
                case ({y_odd_d, x_odd_d})

                    2'b00: begin
                        // even y, even x
                        // Output A
                        pixel_out <= read_data;

                        // Store source row pixel for the next VGA row
                        line_buffer[read_x_d] <= read_data;
                    end

                    2'b01: begin
                        // even y, odd x
                        // Output avg(A, B)
                        pixel_out <= avg2(prev_pixel, read_data);

                        // Store source row pixel for the next VGA row
                        line_buffer[read_x_d] <= read_data;
                    end

                    2'b10: begin
                        // odd y, even x
                        // Output avg(A, C)
                        pixel_out <= avg2(line_buffer[src_x_d], read_data);
                    end

                    2'b11: begin
                        // odd y, odd x
                        // Output avg(A, B, C, D)
                        //
                        // A = line_buffer[src_x_d]
                        // B = line_buffer[src_x_next_d]
                        // C = prev_pixel
                        // D = read_data
                        pixel_out <= avg4(
                            line_buffer[src_x_d],
                            line_buffer[src_x_next_d],
                            prev_pixel,
                            read_data
                        );
                    end

                endcase
            end

            // Save current read_data as previous pixel
            prev_pixel <= read_data;

            //====================================================
            // Save current VGA metadata for next-cycle read_data
            //====================================================

            active_d <= active;
            upscale_enable_d <= upscale_enable;

            x_odd_d <= vga_x[0];
            y_odd_d <= vga_y[0];

            src_x_d <= src_x;
            src_x_next_d <= src_x_next;
            read_x_d <= read_x;
        end
    end

endmodule