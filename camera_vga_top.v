`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top Module: OV7670 Camera to VGA Display System
// 
// This module connects the OV7670 camera to a VGA monitor via Basys 3 FPGA
// Resolution: 320x240 captured, displayed at 640x480 (pixel doubled)
//////////////////////////////////////////////////////////////////////////////////

module camera_vga_top(
    input wire clk,              // 100MHz system clock from Basys 3
    input wire reset,            // Reset button
    
    // OV7670 Camera Interface
    input wire [7:0] camera_data,   // D7-D0 from camera
    input wire camera_href,          // Horizontal reference (HRE)
    input wire camera_vsync,         // Vertical sync (VSY)
    input wire camera_pclk,          // Pixel clock from camera
    output wire camera_xclk,         // Master clock to camera (24MHz)
    output wire camera_pwdn,         // Power down (active high)
    output wire camera_reset,        // Camera reset (active low)
    inout wire camera_siod,          // SCCB data line (SDA)
    output wire camera_sioc,         // SCCB clock line (SCL)
    
    // VGA Output
    output wire vga_hsync,
    output wire vga_vsync,
    output wire [3:0] vga_red,
    output wire [3:0] vga_green,
    output wire [3:0] vga_blue,
    
    // Control switches for filters (optional - for future expansion)
    input wire [2:0] filter_sel,
    
    // Debug LEDs
    output wire [3:0] led
);

    // Clock generation
    wire clk_25mhz;      // VGA pixel clock
    wire clk_24mhz;      // Camera master clock
    wire clk_locked;
    
    // Frame buffer signals
    wire [16:0] write_addr;
    wire [11:0] write_data;  // RGB444 format
    wire write_enable;
    wire [16:0] read_addr;
    wire [11:0] read_data;
    
    // Camera configuration status
    wire config_done;
    
    // VGA signals
    wire vga_active;
    wire [9:0] vga_x;
    wire [9:0] vga_y;
    
    // Camera control - keep camera active
    assign camera_pwdn = 1'b0;   // Not in power down
    assign camera_reset = 1'b1;  // Not in reset (active low, so 1 = normal)
    assign camera_xclk = clk_24mhz;
    
    // Debug: show configuration status
    assign led[0] = config_done;
    assign led[1] = camera_vsync;
    assign led[2] = camera_href;
    assign led[3] = write_enable;
    
    //=======================================================================
    // Clock Generation Module
    //=======================================================================
    clk_wiz_0 clk_gen (
        .clk_in1(clk),           // 100 MHz input
        .clk_out1(clk_25mhz),    // 25 MHz for VGA
        .clk_out2(clk_24mhz),    // 24 MHz for camera
        .reset(reset),
        .locked(clk_locked)
    );
    
    //=======================================================================
    // SCCB (I2C-like) Camera Configuration Module
    //=======================================================================
    ov7670_config camera_config (
        .clk(clk),
        .reset(reset || !clk_locked),
        .sioc(camera_sioc),
        .siod(camera_siod),
        .config_done(config_done)
    );
    
    //=======================================================================
    // Camera Capture Module
    //=======================================================================
    ov7670_capture camera_capture (
        .pclk(camera_pclk),
        .vsync(camera_vsync),
        .href(camera_href),
        .data_in(camera_data),
        .reset(reset || !config_done),
        
        .frame_addr(write_addr),
        .frame_pixel(write_data),
        .frame_we(write_enable)
    );
    
    //=======================================================================
    // Frame Buffer (Dual-Port Block RAM)
    // 320x240 = 76,800 pixels = needs 17 bits addressing
    // Stores RGB444 (12 bits per pixel)
    //=======================================================================
    frame_buffer fb (
        // Write port (camera side)
        .clka(camera_pclk),
        .wea(write_enable),
        .addra(write_addr),
        .dina(write_data),
        
        // Read port (VGA side)
        .clkb(clk_25mhz),
        .addrb(read_addr),
        .doutb(read_data)
    );
    
    //=======================================================================
    // VGA Controller Signals (Internal)
    //=======================================================================
    wire w_vga_hsync;
    wire w_vga_vsync;
    wire w_vga_active;
    wire [9:0] w_vga_x;
    wire [9:0] w_vga_y;

    vga_controller vga_ctrl (
        .clk(clk_25mhz),
        .reset(reset),
        
        .hsync(w_vga_hsync),
        .vsync(w_vga_vsync),
        .active(w_vga_active),
        .x_pos(w_vga_x),
        .y_pos(w_vga_y)
    );
    
    //=======================================================================
    // VGA Read Address Generator (with pixel doubling)
    // 320 = 256 + 64 -> (y * 256) + (y * 64) -> (y << 8) + (y << 6)
    //=======================================================================
    wire [8:0] y_val = w_vga_y[9:1];
    wire [8:0] x_val = w_vga_x[9:1];
    assign read_addr = (y_val << 8) + (y_val << 6) + x_val;

    //=======================================================================
    // 2. ปรับปรุงเรื่อง BRAM Latency (หน่วงสัญญาณ Sync ให้รอข้อมูลภาพ 1 Clock)
    //=======================================================================
    reg r_vga_hsync, r_vga_vsync, r_vga_active;
    
    always @(posedge clk_25mhz) begin
        r_vga_hsync  <= w_vga_hsync;
        r_vga_vsync  <= w_vga_vsync;
        r_vga_active <= w_vga_active;
    end
    
    // ต่อออกพอร์ตของ Module จริงๆ
    assign vga_hsync = r_vga_hsync;
    assign vga_vsync = r_vga_vsync;
    
    //=======================================================================
    // VGA Output (apply filters based on switches)
    //=======================================================================
    wire [11:0] filtered_pixel;
    
    image_filter filter (
        .pixel_in(read_data),
        .filter_sel(filter_sel),
        .pixel_out(filtered_pixel)
    );
    
    // ใช้สัญญาณ Active ที่ถูกหน่วงเวลาแล้วมาควบคุม Output
    assign vga_red   = r_vga_active ? filtered_pixel[11:8] : 4'b0000;
    assign vga_green = r_vga_active ? filtered_pixel[7:4]  : 4'b0000;
    assign vga_blue  = r_vga_active ? filtered_pixel[3:0]  : 4'b0000;
    
endmodule
