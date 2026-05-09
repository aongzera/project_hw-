`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OV7670 Camera Capture Module - FIXED VERSION
//
// Captures RGB565 from OV7670 and stores RGB444 pixels into the frame buffer.
// The camera outputs one byte per PCLK. Two bytes make one RGB565 pixel:
//   byte1 = R[4:0] G[5:3]
//   byte2 = G[2:0] B[4:0]
//
// Main fixes:
// 1) Reset byte phase at every HREF rising/falling edge so lines do not become
//    shifted if one byte is missed.
// 2) Use VSYNC high as frame blank/reset, which matches normal OV7670 timing.
// 3) Drop pixels outside 320x240 instead of wrapping/smearing addresses.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_capture #(
    parameter FRAME_WIDTH  = 320,
    parameter FRAME_HEIGHT = 240
)(
    input  wire       pclk,        // Pixel clock from camera
    input  wire       vsync,       // High during vertical blank for OV7670
    input  wire       href,        // High while line data is valid
    input  wire [7:0] data_in,     // Camera D[7:0]
    input  wire       reset,

    output reg [16:0] frame_addr,  // 0..76799
    output reg [11:0] frame_pixel, // RGB444
    output reg        frame_we
);

    reg [7:0] byte1;
    reg       byte_phase;          // 0 = waiting for byte1, 1 = waiting for byte2
    reg       href_d;
    reg [8:0] pixel_x;             // 0..319, with overflow guard
    reg [8:0] pixel_y;             // 0..239, with overflow guard

    wire href_rise =  href && !href_d;
    wire href_fall = !href &&  href_d;

    // Convert RGB565 to RGB444.
    wire [3:0] r444 = byte1[7:4];
    wire [3:0] g444 = {byte1[2:0], data_in[7]};
    wire [3:0] b444 = data_in[4:1];

    always @(posedge pclk or posedge reset) begin
        if (reset) begin
            byte1       <= 8'd0;
            byte_phase  <= 1'b0;
            href_d      <= 1'b0;
            pixel_x     <= 9'd0;
            pixel_y     <= 9'd0;
            frame_addr  <= 17'd0;
            frame_pixel <= 12'd0;
            frame_we    <= 1'b0;
        end else begin
            href_d   <= href;
            frame_we <= 1'b0;

            // During VSYNC high, camera is between frames. Prepare for the
            // next frame. This also prevents accidental writes during blanking.
            if (vsync) begin
                pixel_x    <= 9'd0;
                pixel_y    <= 9'd0;
                byte_phase <= 1'b0;
            end else begin
                // New active line: restart x and byte pair alignment.
                if (href_rise) begin
                    pixel_x    <= 9'd0;
                    byte_phase <= 1'b0;
                end

                // End of active line: go to next row and reset byte alignment.
                if (href_fall) begin
                    byte_phase <= 1'b0;
                    if (pixel_y < FRAME_HEIGHT) begin
                        pixel_y <= pixel_y + 9'd1;
                    end
                end

                // Capture only while HREF is high.
                if (href) begin
                    if (byte_phase == 1'b0) begin
                        byte1      <= data_in;
                        byte_phase <= 1'b1;
                    end else begin
                        if ((pixel_x < FRAME_WIDTH) && (pixel_y < FRAME_HEIGHT)) begin
                            frame_pixel <= {r444, g444, b444};
                            frame_addr  <= (pixel_y * FRAME_WIDTH) + pixel_x;
                            frame_we    <= 1'b1;
                        end

                        if (pixel_x < FRAME_WIDTH) begin
                            pixel_x <= pixel_x + 9'd1;
                        end
                        byte_phase <= 1'b0;
                    end
                end
            end
        end
    end

endmodule