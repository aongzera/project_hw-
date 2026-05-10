`timescale 1ns / 1ps

module ov7670_capture_line #(
    parameter FRAME_WIDTH  = 640,
    parameter FRAME_HEIGHT = 480
)(
    input  wire        pclk,
    input  wire        reset,

    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  data_in,

    input  wire        byte_swap,
    input  wire        pclk_invert,

    output reg  [9:0]  pixel_x,
    output reg  [9:0]  pixel_y,
    output reg  [9:0]  line_addr,
    output reg  [11:0] line_pixel,
    output reg         line_we,

    output reg         frame_active,
    output reg         new_frame_pulse,
    output reg         new_line_pulse
);

    localparam WAIT_BYTE1 = 1'b0;
    localparam WAIT_BYTE2 = 1'b1;

    reg state;
    reg [7:0] byte1;

    reg prev_vsync;
    reg prev_href;

    // Optional: sample on falling edge if camera data is unstable on rising edge
    reg [7:0] data_neg;
    always @(negedge pclk) begin
        data_neg <= data_in;
    end

    wire [7:0] data_use = pclk_invert ? data_neg : data_in;

    // RGB565 decode
    wire [3:0] r_normal = byte1[7:4];
    wire [3:0] g_normal = {byte1[2:0], data_use[7]};
    wire [3:0] b_normal = data_use[4:1];

    wire [3:0] r_swap = data_use[7:4];
    wire [3:0] g_swap = {data_use[2:0], byte1[7]};
    wire [3:0] b_swap = byte1[4:1];

    wire [3:0] r = byte_swap ? r_swap : r_normal;
    wire [3:0] g = byte_swap ? g_swap : g_normal;
    wire [3:0] b = byte_swap ? b_swap : b_normal;

    always @(posedge pclk or posedge reset) begin
        if (reset) begin
            state           <= WAIT_BYTE1;
            byte1           <= 8'd0;

            pixel_x         <= 10'd0;
            pixel_y         <= 10'd0;
            line_addr       <= 10'd0;
            line_pixel      <= 12'd0;
            line_we         <= 1'b0;

            frame_active    <= 1'b0;
            new_frame_pulse <= 1'b0;
            new_line_pulse  <= 1'b0;

            prev_vsync      <= 1'b1;
            prev_href       <= 1'b0;
        end else begin
            prev_vsync <= vsync;
            prev_href  <= href;

            line_we         <= 1'b0;
            new_frame_pulse <= 1'b0;
            new_line_pulse  <= 1'b0;

            // Start of frame: OV7670 VSYNC usually goes low during active frame
            if (prev_vsync && !vsync) begin
                frame_active    <= 1'b1;
                pixel_x         <= 10'd0;
                pixel_y         <= 10'd0;
                state           <= WAIT_BYTE1;
                new_frame_pulse <= 1'b1;
            end

            // End of frame
            if (!prev_vsync && vsync) begin
                frame_active <= 1'b0;
            end

            // End of line
            if (frame_active && prev_href && !href) begin
                pixel_x        <= 10'd0;
                state          <= WAIT_BYTE1;
                new_line_pulse <= 1'b1;

                if (pixel_y < FRAME_HEIGHT - 1) begin
                    pixel_y <= pixel_y + 10'd1;
                end
            end

            // Active pixel capture
            if (frame_active && href) begin
                case (state)
                    WAIT_BYTE1: begin
                        byte1 <= data_use;
                        state <= WAIT_BYTE2;
                    end

                    WAIT_BYTE2: begin
                        if (pixel_x < FRAME_WIDTH && pixel_y < FRAME_HEIGHT) begin
                            line_addr  <= pixel_x;
                            line_pixel <= {r, g, b};
                            line_we    <= 1'b1;
                        end

                        if (pixel_x < FRAME_WIDTH) begin
                            pixel_x <= pixel_x + 10'd1;
                        end

                        state <= WAIT_BYTE1;
                    end
                endcase
            end
        end
    end

endmodule