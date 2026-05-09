`timescale 1ns / 1ps

module vga_display(
    input  wire        clk_25MHz,    // 25 MHz VGA clock
    input  wire        reset,        // Reset button

    // Frame Buffer (BRAM) Interface
    output wire [16:0] frame_addr,   // Read address (0 to 76799)
    input  wire [11:0] frame_pixel,  // 12-bit pixel data from BRAM (1 clock latency)

    // Physical VGA Output
    output reg         hsync_out,    // Delayed HSYNC
    output reg         vsync_out,    // Delayed VSYNC
    output wire [3:0]  vga_r,        // Red channel
    output wire [3:0]  vga_g,        // Green channel
    output wire [3:0]  vga_b         // Blue channel
);

    // -------------------------------------------------------------------------
    // 1. Generate VGA timing and coordinates
    // -------------------------------------------------------------------------
    wire vga_hsync, vga_vsync, vga_active;
    wire [9:0] x_pos;
    wire [9:0] y_pos;

    vga_controller vga_timing_inst (
        .clk    (clk_25MHz),
        .reset  (reset),
        .hsync  (vga_hsync),
        .vsync  (vga_vsync),
        .active (vga_active),
        .x_pos  (x_pos),
        .y_pos  (y_pos)
    );

    // -------------------------------------------------------------------------
    // 2. Pixel Doubling and Address Calculation
    // -------------------------------------------------------------------------
    // Divide 640x480 coordinates by 2 to map to 320x240 resolution
    wire [8:0] img_x = x_pos >> 1;
    wire [8:0] img_y = y_pos >> 1;

    // Calculate 1D address (Y * 320 + X)
    // Cast 320 to 17 bits to prevent overflow during multiplication
    assign frame_addr = (img_y * 17'd320) + img_x;

    // -------------------------------------------------------------------------
    // 3. BRAM Read Latency Compensation (1 Clock Cycle)
    // -------------------------------------------------------------------------
    reg active_d; // Delayed active signal

    always @(posedge clk_25MHz or posedge reset) begin
        if (reset) begin
            hsync_out <= 1'b1; // HSYNC is active low
            vsync_out <= 1'b1; // VSYNC is active low
            active_d  <= 1'b0;
        end else begin
            // Delay sync signals by 1 clock to match BRAM output latency
            hsync_out <= vga_hsync;
            vsync_out <= vga_vsync;
            active_d  <= vga_active;
        end
    end

    // -------------------------------------------------------------------------
    // 4. Color Output
    // -------------------------------------------------------------------------
    // Output pixel data only during active display region.
    // Blanking region must be completely black (0).
    assign vga_r = active_d ? frame_pixel[11:8] : 4'h0;
    assign vga_g = active_d ? frame_pixel[7:4]  : 4'h0;
    assign vga_b = active_d ? frame_pixel[3:0]  : 4'h0;

endmodule