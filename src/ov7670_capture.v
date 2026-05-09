`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OV7670 Camera Capture Module (Upgraded to Full VGA 640x480 / 3-bit RGB)
//
// Captures pixel data from the OV7670 camera and writes to frame buffer
// Input: RGB565 from camera (2 bytes per pixel)
// Output: 3-bit RGB to frame buffer (3 bits per pixel to save BRAM)
// Resolution: 640x480 pixels
//////////////////////////////////////////////////////////////////////////////////

module ov7670_capture(
    input wire pclk,              // Pixel clock from camera (~24MHz)
    input wire vsync,             // Vertical sync (1 during blank, 0 during frame)
    input wire href,              // Horizontal reference (1 during valid line)
    input wire [7:0] data_in,     // Pixel data from camera
    input wire reset,
    input wire byte_swap,         // 0 = RGB565 byte0=RG/byte1=GB (datasheet),
                                  // 1 = swapped (some modules need this)
    input wire yuv_mode,          // 1 = treat byte0 as Y luma -> grayscale.
    input wire pclk_invert,       // 1 = sample data half a PCLK cycle later

    output reg [18:0] frame_addr,  // Address in frame buffer (0-307199) *** แก้เป็น 19 บิต
    output reg [2:0] frame_pixel,  // 3-bit RGB pixel data *** แก้เป็น 3 บิต
    output reg frame_we            // Write enable
);

    parameter FRAME_WIDTH  = 640;  // *** อัปเกรดเป็น 640
    parameter FRAME_HEIGHT = 480;  // *** อัปเกรดเป็น 480

    // Capture sub-states (which byte of the 2-byte RGB565 pixel)
    localparam WAIT_FRAME    = 2'd0;
    localparam CAPTURE_BYTE1 = 2'd1;
    localparam CAPTURE_BYTE2 = 2'd2;

    reg [1:0] state;
    reg [7:0] byte1;
    reg       prev_vsync;
    reg       prev_href;
    reg       frame_active;

    reg [9:0] pixel_x;             // 0..639 (*** ขยายเป็น 10 บิต)
    reg [9:0] pixel_y;             // 0..479 (*** ขยายเป็น 10 บิต)

    // ---- Optional half-cycle data realignment (SW5 = pclk_invert) ----
    reg  [7:0] data_neg;
    always @(negedge pclk) data_neg <= data_in;
    wire [7:0] data_use = pclk_invert ? data_neg : data_in;

    // ---- RGB565 unpack (two possible byte orders) ----
    wire [3:0] rgb_r_normal = byte1[7:4];
    wire [3:0] rgb_g_normal = {byte1[2:0],  data_use[7]};
    wire [3:0] rgb_b_normal = data_use[4:1];

    wire [3:0] rgb_r_swap   = data_use[7:4];
    wire [3:0] rgb_g_swap   = {data_use[2:0], byte1[7]};
    wire [3:0] rgb_b_swap   = byte1[4:1];

    wire [3:0] rgb_r        = byte_swap ? rgb_r_swap : rgb_r_normal;
    wire [3:0] rgb_g        = byte_swap ? rgb_g_swap : rgb_g_normal;
    wire [3:0] rgb_b        = byte_swap ? rgb_b_swap : rgb_b_normal;

    // ---- YUV422 -> RGB444 conversion (BT.601, fixed-point with 64x scale) ----
    reg [7:0] cb_save;
    reg [7:0] cr_save;

    wire [7:0] yuv_y      = byte_swap ? data_use : byte1;
    wire [7:0] yuv_chroma = byte_swap ? byte1    : data_use;
    wire [7:0] yuv_cb     = pixel_x[0] ? cb_save     : yuv_chroma;
    wire [7:0] yuv_cr     = pixel_x[0] ? yuv_chroma  : cr_save;

    function [11:0] yuv_to_rgb444;
        input [7:0] y;
        input [7:0] cb;
        input [7:0] cr;
        reg signed [11:0] cb_d, cr_d;
        reg signed [19:0] y64, r_s, g_s, b_s;
        reg [7:0] r_8, g_8, b_8;
        begin
            cb_d = $signed({4'b0, cb}) - 12'sd128;
            cr_d = $signed({4'b0, cr}) - 12'sd128;
            y64  = $signed({12'b0, y, 6'b0});
            r_s  = y64                + cr_d * 12'sd90;
            g_s  = y64 - cb_d * 12'sd22 - cr_d * 12'sd46;
            b_s  = y64 + cb_d * 12'sd113;
            if      (r_s < 0)            r_8 = 8'h00;
            else if (r_s > 20'sd16320)   r_8 = 8'hFF;
            else                         r_8 = r_s[13:6];
            if      (g_s < 0)            g_8 = 8'h00;
            else if (g_s > 20'sd16320)   g_8 = 8'hFF;
            else                         g_8 = g_s[13:6];
            if      (b_s < 0)            b_8 = 8'h00;
            else if (b_s > 20'sd16320)   b_8 = 8'hFF;
            else                         b_8 = b_s[13:6];
            yuv_to_rgb444 = {r_8[7:4], g_8[7:4], b_8[7:4]};
        end
    endfunction

    wire [11:0] yuv_pixel = yuv_to_rgb444(yuv_y, yuv_cb, yuv_cr);

    wire [3:0] rgb444_r = yuv_mode ? yuv_pixel[11:8] : rgb_r;
    wire [3:0] rgb444_g = yuv_mode ? yuv_pixel[7:4]  : rgb_g;
    wire [3:0] rgb444_b = yuv_mode ? yuv_pixel[3:0]  : rgb_b;

    always @(posedge pclk or posedge reset) begin
        if (reset) begin
            state        <= WAIT_FRAME;
            frame_addr   <= 19'd0;
            frame_pixel  <= 3'd0;
            frame_we     <= 1'b0;
            pixel_x      <= 10'd0;
            pixel_y      <= 10'd0;
            frame_active <= 1'b0;
            prev_vsync   <= 1'b1;
            prev_href    <= 1'b0;
            byte1        <= 8'd0;
            cb_save      <= 8'd128;
            cr_save      <= 8'd128;
        end else begin
            prev_vsync <= vsync;
            prev_href  <= href;
            frame_we <= 1'b0;

            // 1. End-of-line: HREF falling edge.
            if (frame_active && prev_href && !href) begin
                state   <= WAIT_FRAME;
                pixel_x <= 10'd0;
                if (pixel_y < FRAME_HEIGHT) begin
                    pixel_y <= pixel_y + 10'd1;
                end
            end

            // 2. Active capture during HREF high
            if (frame_active && href) begin
                case (state)
                    WAIT_FRAME: begin
                        byte1 <= data_use;
                        state <= CAPTURE_BYTE2;
                    end

                    CAPTURE_BYTE1: begin
                        byte1 <= data_use;
                        state <= CAPTURE_BYTE2;
                    end

                    CAPTURE_BYTE2: begin
                        if (pixel_x < FRAME_WIDTH && pixel_y < FRAME_HEIGHT) begin
                            // *** บีบอัดสี: ดึงเฉพาะบิตสว่างสุด (MSB) ของ R, G, B มาประกอบเป็น 3-bit
                            frame_pixel <= {rgb444_r[3], rgb444_g[3], rgb444_b[3]};
                            
                            // *** คำนวณ Address ใหม่สำหรับขนาด 640x480
                            frame_addr  <= (pixel_y * FRAME_WIDTH) + pixel_x;
                            frame_we    <= 1'b1;
                        end
                        
                        if (yuv_mode) begin
                            if (pixel_x[0] == 1'b0) cb_save <= yuv_chroma;
                            else                    cr_save <= yuv_chroma;
                        end
                        if (pixel_x < FRAME_WIDTH) begin
                            pixel_x <= pixel_x + 10'd1;
                        end
                        state <= CAPTURE_BYTE1;
                    end

                    default: state <= WAIT_FRAME;
                endcase
            end

            // 3. End-of-frame: VSYNC rising edge
            if (!prev_vsync && vsync) begin
                frame_active <= 1'b0;
            end

            // 4. Start-of-frame: VSYNC falling edge 
            if (prev_vsync && !vsync) begin
                frame_active <= 1'b1;
                pixel_x      <= 10'd0;
                pixel_y      <= 10'd0;
                state        <= WAIT_FRAME;
            end
        end
    end

endmodule