`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OV7670 Camera Capture Module
//
// Captures pixel data from the OV7670 camera and writes to frame buffer
// Input: RGB565 from camera (2 bytes per pixel)
// Output: RGB444 to frame buffer (12 bits per pixel)
// Resolution: 320x240 pixels
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
                                  //     Useful if SCCB never configured the
                                  //     camera and it stayed in default YUV.
    input wire pclk_invert,       // 1 = sample data half a PCLK cycle later
                                  //     (equivalent to inverting PCLK edge).
                                  //     Try if the image is garbled noise.

    output reg [16:0] frame_addr,  // Address in frame buffer (0-76799)
    output reg [11:0] frame_pixel, // RGB444 pixel data
    output reg frame_we            // Write enable
);

    parameter FRAME_WIDTH  = 320;
    parameter FRAME_HEIGHT = 240;

    // Capture sub-states (which byte of the 2-byte RGB565 pixel)
    localparam WAIT_FRAME    = 2'd0;
    localparam CAPTURE_BYTE1 = 2'd1;
    localparam CAPTURE_BYTE2 = 2'd2;

    reg [1:0] state;
    reg [7:0] byte1;
    reg       prev_vsync;
    reg       prev_href;
    reg       frame_active;

    reg [8:0] pixel_x;             // 0..319 (one extra bit for safe overflow check)
    reg [8:0] pixel_y;             // 0..239 (one extra bit for safe overflow check)

    // ---- Optional half-cycle data realignment (SW5 = pclk_invert) ----
    // If the OV7670 presents valid data on the falling edge of PCLK but the
    // FSM samples on the rising edge, every byte we read is mid-transition
    // and you get garbage with motion bleeding through. Capturing on the
    // opposite (negedge) and muxing in here is equivalent to inverting PCLK,
    // without creating a second clock domain.
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
    // OV7670 default YUV422 byte order (TSLB[3]=0): Y0 Cb Y1 Cr Y0 Cb Y1 Cr ...
    // In our 2-byte-per-pixel capture:
    //   byte1 (= 1st byte of pair) is always Y.
    //   data_use (= 2nd byte of pair) is Cb on EVEN pixels, Cr on ODD pixels.
    // Cb and Cr are SHARED between adjacent pixel pairs. We save the most
    // recent Cb when capturing an even pixel, and use it for the odd pixel.
    // We save the most recent Cr from each odd pixel to use with the NEXT
    // even pixel (1-pair lag, visually invisible).
    reg [7:0] cb_save;
    reg [7:0] cr_save;

    // byte_swap (SW3) also picks which captured byte is Y vs chroma:
    //   byte_swap=0  -> 1st byte is Y, 2nd byte is Cb/Cr  (datasheet default)
    //   byte_swap=1  -> 1st byte is Cb/Cr, 2nd byte is Y  (some modules)
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
            frame_addr   <= 17'd0;
            frame_pixel  <= 12'd0;
            frame_we     <= 1'b0;
            pixel_x      <= 9'd0;
            pixel_y      <= 9'd0;
            frame_active <= 1'b0;
            prev_vsync   <= 1'b1;
            prev_href    <= 1'b0;
            byte1        <= 8'd0;
            cb_save      <= 8'd128;
            cr_save      <= 8'd128;
        end else begin
            // Edge-detect helpers
            prev_vsync <= vsync;
            prev_href  <= href;

            // Default: do not write this cycle
            frame_we <= 1'b0;

            //--------------------------------------------------------------
            // 1. End-of-line: HREF falling edge.  Reset the byte phase and
            //    advance to the next row REGARDLESS of which sub-state we
            //    were in.  This is the bug that caused only the topmost
            //    line of pixels to appear — pixel_y was previously bumped
            //    only when the line ended in CAPTURE_BYTE1, but with 320
            //    pixels (640 bytes) per line the line always ended while
            //    the FSM was in CAPTURE_BYTE2, so pixel_y stayed at 0.
            //--------------------------------------------------------------
            if (frame_active && prev_href && !href) begin
                state   <= WAIT_FRAME;
                pixel_x <= 9'd0;
                if (pixel_y < FRAME_HEIGHT) begin
                    pixel_y <= pixel_y + 9'd1;
                end
            end

            //--------------------------------------------------------------
            // 2. Active capture during HREF high
            //--------------------------------------------------------------
            if (frame_active && href) begin
                case (state)
                    WAIT_FRAME: begin
                        // HREF just went high — sample byte 0 immediately
                        byte1 <= data_use;
                        state <= CAPTURE_BYTE2;
                    end

                    CAPTURE_BYTE1: begin
                        byte1 <= data_use;
                        state <= CAPTURE_BYTE2;
                    end

                    CAPTURE_BYTE2: begin
                        // Second byte arrived: assemble pixel and write.
                        if (pixel_x < FRAME_WIDTH && pixel_y < FRAME_HEIGHT) begin
                            frame_pixel <= {rgb444_r, rgb444_g, rgb444_b};
                            frame_addr  <= (pixel_y * FRAME_WIDTH) + pixel_x;
                            frame_we    <= 1'b1;
                        end
                        // YUV path: cache the chroma we just consumed so it
                        // can pair with the next pixel.
                        if (yuv_mode) begin
                            if (pixel_x[0] == 1'b0) cb_save <= yuv_chroma;
                            else                    cr_save <= yuv_chroma;
                        end
                        if (pixel_x < FRAME_WIDTH) begin
                            pixel_x <= pixel_x + 9'd1;
                        end
                        state <= CAPTURE_BYTE1;
                    end

                    default: state <= WAIT_FRAME;
                endcase
            end

            //--------------------------------------------------------------
            // 3. End-of-frame: VSYNC rising edge
            //--------------------------------------------------------------
            if (!prev_vsync && vsync) begin
                frame_active <= 1'b0;
            end

            //--------------------------------------------------------------
            // 4. Start-of-frame: VSYNC falling edge (highest priority,
            //    placed last so it overrides line/byte bookkeeping above).
            //--------------------------------------------------------------
            if (prev_vsync && !vsync) begin
                frame_active <= 1'b1;
                pixel_x      <= 9'd0;
                pixel_y      <= 9'd0;
                state        <= WAIT_FRAME;
            end
        end
    end

endmodule
