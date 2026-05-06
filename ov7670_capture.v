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

    // RGB565 layout across the two bytes:
    //   byte1 = R[4:0], G[5:3]
    //   data_in (byte2) = G[2:0], B[4:0]
    // Convert to RGB444 by keeping the upper 4 bits of each channel.
    wire [3:0] rgb444_r = byte1[7:4];
    wire [3:0] rgb444_g = {byte1[2:0], data_in[7]};
    wire [3:0] rgb444_b = data_in[4:1];

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
                        byte1 <= data_in;
                        state <= CAPTURE_BYTE2;
                    end

                    CAPTURE_BYTE1: begin
                        byte1 <= data_in;
                        state <= CAPTURE_BYTE2;
                    end

                    CAPTURE_BYTE2: begin
                        // Second byte arrived: assemble pixel and write.
                        // Drop pixels beyond the frame edge instead of
                        // smearing them onto the last valid column/row.
                        if (pixel_x < FRAME_WIDTH && pixel_y < FRAME_HEIGHT) begin
                            frame_pixel <= {rgb444_r, rgb444_g, rgb444_b};
                            frame_addr  <= (pixel_y * FRAME_WIDTH) + pixel_x;
                            frame_we    <= 1'b1;
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
