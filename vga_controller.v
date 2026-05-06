`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// VGA Controller Module
//
// Generates VGA timing signals for 640x480 @ 60Hz from a 25 MHz pixel clock.
//
// VGA Timing Parameters (VESA 640x480@60):
//   Horizontal: 640 active + 16 front + 96 sync + 48 back = 800 pixels/line
//   Vertical  : 480 active + 10 front +  2 sync + 33 back = 525 lines/frame
//   HSYNC and VSYNC are both ACTIVE LOW.
//
// All outputs (hsync, vsync, active, x_pos, y_pos) are aligned to the same
// clock edge so that downstream logic (frame buffer read, filter pipeline)
// sees a consistent view of the current pixel position.
//////////////////////////////////////////////////////////////////////////////////

module vga_controller(
    input  wire clk,           // 25 MHz pixel clock
    input  wire reset,

    output reg  hsync,         // Horizontal sync (active LOW)
    output reg  vsync,         // Vertical   sync (active LOW)
    output reg  active,        // High during 640x480 visible region
    output wire [9:0] x_pos,   // Current X (0..H_TOTAL-1)
    output wire [9:0] y_pos    // Current Y (0..V_TOTAL-1)
);

    // Horizontal timing (pixels)
    parameter H_DISPLAY = 640;
    parameter H_FRONT   = 16;
    parameter H_SYNC    = 96;
    parameter H_BACK    = 48;
    parameter H_TOTAL   = H_DISPLAY + H_FRONT + H_SYNC + H_BACK; // 800

    // Vertical timing (lines)
    parameter V_DISPLAY = 480;
    parameter V_FRONT   = 10;
    parameter V_SYNC    = 2;
    parameter V_BACK    = 33;
    parameter V_TOTAL   = V_DISPLAY + V_FRONT + V_SYNC + V_BACK; // 525

    // Position counters
    reg [9:0] h_count;
    reg [9:0] v_count;

    assign x_pos = h_count;
    assign y_pos = v_count;

    // Next-state of the counters (one combinational copy used everywhere
    // below, so hsync / vsync / active land on the SAME clock edge as
    // h_count / v_count and stay in phase with x_pos / y_pos).
    wire        h_end  = (h_count == H_TOTAL - 1);
    wire        v_end  = (v_count == V_TOTAL - 1);
    wire [9:0]  h_next = h_end ? 10'd0
                                : h_count + 10'd1;
    wire [9:0]  v_next = h_end ? (v_end ? 10'd0 : v_count + 10'd1)
                                : v_count;

    // Single synchronous block keeps every output phase-aligned.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
            hsync   <= 1'b1;
            vsync   <= 1'b1;
            active  <= 1'b0;
        end else begin
            h_count <= h_next;
            v_count <= v_next;

            // Sync pulses: low only while the next position is inside
            // the sync window of the blanking interval.
            hsync <= ~((h_next >= (H_DISPLAY + H_FRONT)) &&
                       (h_next <  (H_DISPLAY + H_FRONT + H_SYNC)));
            vsync <= ~((v_next >= (V_DISPLAY + V_FRONT)) &&
                       (v_next <  (V_DISPLAY + V_FRONT + V_SYNC)));

            // Visible region for the upcoming pixel.
            active <= (h_next < H_DISPLAY) && (v_next < V_DISPLAY);
        end
    end

endmodule
