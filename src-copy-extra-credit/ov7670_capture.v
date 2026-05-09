`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OV7670 Camera Capture Module (640x480 Line-Buffer Version)
//////////////////////////////////////////////////////////////////////////////////

module ov7670_capture(
    input wire pclk,              // ~24MHz Pixel Clock
    input wire vsync,             // Vertical Sync
    input wire href,              // Horizontal Reference
    input wire [7:0] data_in,     // Raw 8-bit data
    input wire reset,
    input wire byte_swap,         // RGB565 byte order toggle
    input wire yuv_mode,          // Treat as YUV -> Grayscale
    input wire pclk_invert,       // Sample on different edge

    output reg [9:0]  pixel_x,    // Column index (0-639)
    output reg [9:0]  pixel_y,    // Row index (0-479)
    output reg [11:0] frame_pixel,// RGB444 output
    output reg        frame_we    // Pulse when 1 pixel is ready
);
    parameter FRAME_WIDTH  = 640;
    parameter FRAME_HEIGHT = 480;

    localparam WAIT_FRAME    = 2'd0;
    localparam CAPTURE_BYTE1 = 2'd1;
    localparam CAPTURE_BYTE2 = 2'd2;

    reg [1:0] state;
    reg [7:0] byte1;
    reg       prev_vsync, prev_href;
    reg       frame_active;

    // Optional half-cycle data realignment
    reg [7:0] data_neg;
    always @(negedge pclk) data_neg <= data_in;
    wire [7:0] data_use = pclk_invert ? data_neg : data_in;

    // RGB565 Unpack Logic
    wire [3:0] rgb_r_normal = byte1[7:4];
    wire [3:0] rgb_g_normal = {byte1[2:0], data_use[7]};
    wire [3:0] rgb_b_normal = data_use[4:1];

    wire [3:0] rgb_r_swap   = data_use[7:4];
    wire [3:0] rgb_g_swap   = {data_use[2:0], byte1[7]};
    wire [3:0] rgb_b_swap   = byte1[4:1];

    wire [3:0] r = byte_swap ? rgb_r_swap : rgb_r_normal;
    wire [3:0] g = byte_swap ? rgb_g_swap : rgb_g_normal;
    wire [3:0] b = byte_swap ? rgb_b_swap : rgb_b_normal;

    always @(posedge pclk or posedge reset) begin
        if (reset) begin
            state <= WAIT_FRAME; pixel_x <= 0; pixel_y <= 0;
            frame_pixel <= 0; frame_we <= 0; frame_active <= 0;
            prev_vsync <= 1; prev_href <= 0; byte1 <= 0;
        end else begin
            prev_vsync <= vsync;
            prev_href <= href;
            frame_we <= 0;

            // End of line detection
            if (frame_active && prev_href && !href) begin
                state <= WAIT_FRAME;
                pixel_x <= 0;
                if (pixel_y < FRAME_HEIGHT - 1) pixel_y <= pixel_y + 1;
            end

            // Active capture during HREF
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
                            frame_pixel <= {r, g, b};
                            frame_we <= 1;
                        end
                        if (pixel_x < FRAME_WIDTH - 1) pixel_x <= pixel_x + 1;
                        state <= CAPTURE_BYTE1;
                    end
                    default: state <= WAIT_FRAME;
                endcase
            end

            // VSYNC detection
            if (!prev_vsync && vsync) frame_active <= 0; // End of Frame
            if (prev_vsync && !vsync) begin             // Start of Frame
                frame_active <= 1;
                pixel_x <= 0;
                pixel_y <= 0;
                state <= WAIT_FRAME;
            end
        end
    end
endmodule
