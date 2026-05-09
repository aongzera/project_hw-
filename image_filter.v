`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Image Filter Module
// 
// Implements three image processing filters:
// 000: No filter (original image)
// 001: Grayscale conversion
// 010: Threshold (black/white)
// 011: Red channel only
// 100: Green channel only
// 101: Blue channel only
//////////////////////////////////////////////////////////////////////////////////

module image_filter(
    input wire [11:0] pixel_in,    // RGB444 input
    input wire [2:0] filter_sel,   // Filter selection
    output reg [11:0] pixel_out    // RGB444 output
);

    // Extract color channels
    wire [3:0] red_in   = pixel_in[11:8];
    wire [3:0] green_in = pixel_in[7:4];
    wire [3:0] blue_in  = pixel_in[3:0];

    // Intermediate output channels
    reg [3:0] red_out;
    reg [3:0] green_out;
    reg [3:0] blue_out;

    // Grayscale calculation
    // Y = 0.299R + 0.587G + 0.114B
    // Approximation: Y = (5R + 9G + 2B) / 16
    wire [7:0] gray_calc =
        ({4'b0000, red_in} << 2) + {4'b0000, red_in} +       // 5R
        ({4'b0000, green_in} << 3) + {4'b0000, green_in} +   // 9G
        ({4'b0000, blue_in} << 1);                           // 2B

    wire [3:0] gray = gray_calc[7:4]; // divide by 16

    // Threshold based on grayscale value
    wire is_bright = (gray > 4'd8);

    always @(*) begin
        case (filter_sel)

            3'b001: begin
                // Grayscale filter
                red_out   = gray;
                green_out = gray;
                blue_out  = gray;
            end

            3'b010: begin
                // Threshold filter
                if (is_bright) begin
                    red_out   = 4'hF;
                    green_out = 4'hF;
                    blue_out  = 4'hF;
                end
                else begin
                    red_out   = 4'h0;
                    green_out = 4'h0;
                    blue_out  = 4'h0;
                end
            end

            3'b011: begin
                // Red channel isolation
                red_out   = red_in;
                green_out = 4'h0;
                blue_out  = 4'h0;
            end

            3'b100: begin
                // Green channel isolation
                red_out   = 4'h0;
                green_out = green_in;
                blue_out  = 4'h0;
            end

            3'b101: begin
                // Blue channel isolation
                red_out   = 4'h0;
                green_out = 4'h0;
                blue_out  = blue_in;
            end

            default: begin
                // Original image
                red_out   = red_in;
                green_out = green_in;
                blue_out  = blue_in;
            end

        endcase

        pixel_out = {red_out, green_out, blue_out};
    end

endmodule