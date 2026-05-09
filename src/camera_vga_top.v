`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top Module: OV7670 Camera to VGA Display System (Upgraded to Full VGA 640x480)
// 
// This module connects the OV7670 camera to a VGA monitor via Basys 3 FPGA
// Resolution: 640x480 captured and displayed natively (3-bit RGB BRAM saving)
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
    
    // SW0/SW1/SW2 -> filter_sel[2:0]
    input wire [2:0] filter_sel,
    input wire       byte_swap,    // SW3: toggle RGB565 byte ordering
    input wire       yuv_mode,     // SW4: force YUV-grayscale decode
    input wire       pclk_invert,  // SW5: flip PCLK sampling edge

    // Debug LEDs
    output wire [7:0] led
);

    // Clock generation
    wire clk_25mhz;      // VGA pixel clock
    wire clk_24mhz;      // Camera master clock
    wire clk_locked;
    
    // Frame buffer signals (*** อัปเกรด Address เป็น 19 บิต และ Data เป็น 3 บิต ***)
    wire [18:0] write_addr;
    wire [2:0]  write_data;  // 3-bit RGB format
    wire write_enable;
    wire [18:0] read_addr;
    wire [2:0]  read_data;
    
    // Camera configuration status
    wire config_done;
    
    // VGA signals
    wire vga_active;
    wire [9:0] vga_x;
    wire [9:0] vga_y;
    wire [9:0] vga_x_next;
    wire [9:0] vga_y_next;

    //-----------------------------------------------------------------------
    // Camera power-up reset pulse
    //-----------------------------------------------------------------------
    reg [17:0] cam_rst_cnt;
    reg        cam_rst_n;          // active-low reset to camera

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cam_rst_cnt <= 18'd0;
            cam_rst_n   <= 1'b0;          // hold camera in reset
        end else if (!clk_locked) begin
            cam_rst_cnt <= 18'd0;
            cam_rst_n   <= 1'b0;
        end else if (cam_rst_cnt < 18'd200_000) begin   // 2 ms at 100 MHz
            cam_rst_cnt <= cam_rst_cnt + 18'd1;
            cam_rst_n   <= 1'b0;
        end else begin
            cam_rst_n   <= 1'b1;          // release reset
        end
    end

    assign camera_pwdn  = 1'b0;            // not powered down
    assign camera_reset = cam_rst_n;       // active-low reset pulse on boot
    assign camera_xclk  = clk_24mhz;
    
    //-----------------------------------------------------------------------
    // Debug LEDs
    //-----------------------------------------------------------------------
    reg [23:0] pclk_div;
    always @(posedge camera_pclk) pclk_div <= pclk_div + 24'd1;

    reg [7:0] data_prev;
    reg       data_toggle;
    always @(posedge camera_pclk) begin
        data_prev   <= camera_data;
        if (camera_data != data_prev) data_toggle <= ~data_toggle;
    end

    reg vsync_seen;
    always @(posedge clk or posedge reset) begin
        if (reset)              vsync_seen <= 1'b0;
        else if (camera_vsync)  vsync_seen <= 1'b1;
    end

    reg [22:0] xclk_div;
    always @(posedge clk_24mhz) xclk_div <= xclk_div + 23'd1;

    assign led[0] = config_done;
    assign led[1] = camera_vsync;
    assign led[2] = camera_href;
    assign led[3] = write_enable;
    assign led[4] = pclk_div[23];
    assign led[5] = data_toggle;
    assign led[6] = vsync_seen;
    assign led[7] = xclk_div[22];
    
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
    // SCCB Camera Configuration Module
    //=======================================================================
    ov7670_config camera_config (
        .clk(clk),
        .reset(reset || !clk_locked || !cam_rst_n),
        .sioc(camera_sioc),
        .siod(camera_siod),
        .config_done(config_done)
    );
    
    //=======================================================================
    // Camera Capture Module (640x480 native, 3-bit output)
    //=======================================================================
    ov7670_capture camera_capture (
        .pclk(camera_pclk),
        .vsync(camera_vsync),
        .href(camera_href),
        .data_in(camera_data),
        .reset(reset || !config_done),
        .byte_swap(byte_swap),
        .yuv_mode(yuv_mode),
        .pclk_invert(pclk_invert),

        .frame_addr(write_addr),
        .frame_pixel(write_data),
        .frame_we(write_enable)
    );
    
    //=======================================================================
    // Frame Buffer (Dual-Port Block RAM) - 640x480 = 307200 pixels
    // Stores 3-bit RGB (1-bit per color)
    //=======================================================================
    frame_buffer fb (
        .clka(camera_pclk),
        .wea(write_enable),
        .addra(write_addr),
        .dina(write_data),
        
        .clkb(clk_25mhz),
        .addrb(read_addr),
        .doutb(read_data)
    );
    
    //=======================================================================
    // VGA Controller
    //=======================================================================
    vga_controller vga_ctrl (
        .clk(clk_25mhz),
        .reset(reset),

        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .active(vga_active),
        .x_pos(vga_x),
        .y_pos(vga_y),
        .x_next_pos(vga_x_next),
        .y_next_pos(vga_y_next)
    );

    //=======================================================================
    // VGA Read Address Generator (No more pixel doubling)
    // Full 640x480 mapping. Multiplying y by 640.
    //=======================================================================
    assign read_addr = (vga_y_next * 19'd640) + vga_x_next;
    
    //=======================================================================
    // 3-bit to 12-bit Expansion (So we don't have to rewrite image_filter!)
    // read_data[2] = R, read_data[1] = G, read_data[0] = B
    // If bit is 1, it becomes 4'b1111. If 0, it becomes 4'b0000.
    //=======================================================================
    wire [11:0] expanded_read_data;
    assign expanded_read_data = {
        {4{read_data[2]}}, // Red
        {4{read_data[1]}}, // Green
        {4{read_data[0]}}  // Blue
    };

    //=======================================================================
    // VGA Output — apply filter to camera pixel.
    //=======================================================================
    wire [11:0] filtered_pixel;

    image_filter filter (
        .pixel_in(expanded_read_data), // *** ส่งค่าที่ขยายกลับเป็น 12-bit แล้วเข้าไป
        .filter_sel(filter_sel),
        .pixel_out(filtered_pixel)
    );

    // Output RGB to VGA (only during active display region)
    assign vga_red   = vga_active ? filtered_pixel[11:8] : 4'b0000;
    assign vga_green = vga_active ? filtered_pixel[7:4]  : 4'b0000;
    assign vga_blue  = vga_active ? filtered_pixel[3:0]  : 4'b0000;

endmodule