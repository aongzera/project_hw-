`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top Module: OV7670 Camera to VGA Display System (Full VGA 640x480 Line Buffer)
// 
// Resolution: 640x480 captured, displayed at 640x480 (1:1 mapping)
// Memory: 4-Line Circular BRAM Buffer (Extra Credit Architecture)
//////////////////////////////////////////////////////////////////////////////////

module camera_vga_top(
    input wire clk,              // 100MHz system clock from Basys 3
    input wire reset,            // Reset button
    
    // OV7670 Camera Interface
    input wire [7:0] camera_data, 
    input wire camera_href,          
    input wire camera_vsync,         
    input wire camera_pclk,          
    output wire camera_xclk,         
    output wire camera_pwdn,         
    output wire camera_reset,        
    inout wire camera_siod,          
    output wire camera_sioc,         
    
    // VGA Output
    output wire vga_hsync,
    output wire vga_vsync,
    output wire [3:0] vga_red,
    output wire [3:0] vga_green,
    output wire [3:0] vga_blue,
    
    // Switches
    input wire [2:0] filter_sel,   // SW0-SW2: Filter selection
    input wire       byte_swap,    // SW3: RGB565 byte order
    input wire       yuv_mode,     // SW4: YUV mode debug
    input wire       pclk_invert,  // SW5: PCLK edge invert

    // Debug LEDs
    output wire [7:0] led
);

    wire clk_25mhz;      // VGA pixel clock
    wire clk_24mhz;      // Camera master clock
    wire clk_locked;
    
    // Capture to Buffer signals
    wire [9:0] cam_pixel_x;
    wire [9:0] cam_pixel_y;
    wire [11:0] write_data;  
    wire write_enable;
    
    // Configuration status
    wire config_done;
    
    // VGA signals
    wire vga_active;
    wire [9:0] vga_x;
    wire [9:0] vga_y;
    wire [9:0] vga_x_next;
    wire [9:0] vga_y_next;

    // Buffer read signals
    wire [11:0] read_data;

    //=======================================================================
    // Reset Logic & Debug LEDs
    //=======================================================================
    reg [17:0] cam_rst_cnt;
    reg        cam_rst_n;

    always @(posedge clk or posedge reset) begin
        if (reset || !clk_locked) begin
            cam_rst_cnt <= 18'd0;
            cam_rst_n   <= 1'b0;
        end else if (cam_rst_cnt < 18'd200_000) begin
            cam_rst_cnt <= cam_rst_cnt + 18'd1;
            cam_rst_n   <= 1'b0;
        end else begin
            cam_rst_n   <= 1'b1;
        end
    end

    assign camera_pwdn  = 1'b0;
    assign camera_reset = cam_rst_n;
    assign camera_xclk  = clk_24mhz;

    // LEDs for hardware debugging
    reg [23:0] pclk_div;
    always @(posedge camera_pclk) pclk_div <= pclk_div + 24'd1;
    
    reg [22:0] xclk_div;
    always @(posedge clk_24mhz) xclk_div <= xclk_div + 23'd1;

    assign led[0] = config_done;
    assign led[1] = camera_vsync;
    assign led[2] = camera_href;
    assign led[3] = write_enable;
    assign led[4] = pclk_div[23];
    assign led[7] = xclk_div[22];
    
    //=======================================================================
    // Clock Generation
    //=======================================================================
    clk_wiz_0 clk_gen (
        .clk_in1(clk),
        .clk_out1(clk_25mhz),
        .clk_out2(clk_24mhz),
        .reset(reset),
        .locked(clk_locked)
    );

    //=======================================================================
    // Camera Configuration
    //=======================================================================
    ov7670_config camera_config (
        .clk(clk),
        .reset(reset || !clk_locked || !cam_rst_n),
        .sioc(camera_sioc),
        .siod(camera_siod),
        .config_done(config_done)
    );

    //=======================================================================
    // Camera Capture (Outputs 640x480 coordinates)
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
        .pixel_x(cam_pixel_x),
        .pixel_y(cam_pixel_y),
        .frame_pixel(write_data),
        .frame_we(write_enable)
    );

    //=======================================================================
    // 4-Line Circular Buffer (Replaces Full Frame Buffer)
    //=======================================================================
    // Address format: {Line Index (2 bits), Pixel X (10 bits)}
    wire [11:0] write_addr = {cam_pixel_y[1:0], cam_pixel_x};
    wire [11:0] read_addr  = {vga_y_next[1:0], vga_x_next};

    line_buffer lbuf (
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
    // Image Filter Processing
    //=======================================================================
    wire [11:0] filtered_pixel;
    image_filter filter (
        .pixel_in(read_data),
        .filter_sel(filter_sel),
        .pixel_out(filtered_pixel)
    );

    // Output to VGA Pins
    assign vga_red   = vga_active ? filtered_pixel[11:8] : 4'b0000;
    assign vga_green = vga_active ? filtered_pixel[7:4]  : 4'b0000;
    assign vga_blue  = vga_active ? filtered_pixel[3:0]  : 4'b0000;

endmodule
