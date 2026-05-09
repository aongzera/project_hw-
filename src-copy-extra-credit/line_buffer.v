`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Line Buffer Module (4-Line Circular Buffer for 640x480 VGA)
//
// This module replaces the massive full-frame BRAM. 
// It only stores 4 lines of 640 pixels (4096 addresses needed, using 12-bit addr).
// By using the lowest 2 bits of the Y-coordinate as the line index, 
// it automatically overwrites old lines and acts as a circular buffer.
//////////////////////////////////////////////////////////////////////////////////

module line_buffer(
    // Port A (Write - Camera side running at ~24MHz)
    input wire clka,
    input wire wea,
    input wire [11:0] addra,    // {pixel_y[1:0], pixel_x[9:0]}
    input wire [11:0] dina,     // RGB444 pixel data
    
    // Port B (Read - VGA side running at 25MHz)
    input wire clkb,
    input wire [11:0] addrb,    // {vga_y[1:0], vga_x[9:0]}
    output reg [11:0] doutb     // Output to display/filters
);

    // Block RAM storage: 4096 locations x 12 bits = ~49 Kbits
    // (Easily fits inside the Basys 3's 1800 Kbits limit)
    (* ram_style = "block" *) reg [11:0] ram [0:4095];
    
    // Port A: Write operation (Synchronized to Camera PCLK)
    always @(posedge clka) begin
        if (wea) begin
            ram[addra] <= dina;
        end
    end
    
    // Port B: Read operation (Synchronized to VGA 25MHz Clock)
    always @(posedge clkb) begin
        doutb <= ram[addrb];
    end

endmodule
