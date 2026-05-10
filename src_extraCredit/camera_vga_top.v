`timescale 1ns / 1ps

module camera_vga_top(
    input wire clk,
    input wire reset,

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
    input wire [2:0] filter_sel,
    input wire       byte_swap,
    input wire       pclk_invert,

    // Debug LEDs
    output wire [7:0] led
);

    wire clk_25mhz;
    wire clk_24mhz;
    wire clk_locked;

    wire config_done;

    // Camera capture outputs
    wire [9:0] cam_x;
    wire [9:0] cam_y;
    wire [9:0] line_addr;
    wire [11:0] line_pixel;
    wire line_we;
    wire frame_active;
    wire new_frame_pulse;
    wire new_line_pulse;

    // VGA controller outputs
    wire vga_active;
    wire [9:0] vga_x;
    wire [9:0] vga_y;
    wire [9:0] vga_x_next;
    wire [9:0] vga_y_next;

    wire [11:0] buffer_pixel;
    wire [11:0] filtered_pixel;

    // ============================================================
    // Clock generation
    // ============================================================
    clk_wiz_0 clk_gen (
        .clk_in1(clk),
        .clk_out1(clk_25mhz),    // 25 MHz VGA pixel clock
        .clk_out2(clk_24mhz),    // 24 MHz OV7670 XCLK
        .reset(reset),
        .locked(clk_locked)
    );

    assign camera_xclk = clk_24mhz;
    assign camera_pwdn = 1'b0;

    // ============================================================
    // Camera reset pulse
    // ============================================================
    reg [17:0] cam_rst_cnt;
    reg cam_rst_n;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cam_rst_cnt <= 18'd0;
            cam_rst_n   <= 1'b0;
        end else if (!clk_locked) begin
            cam_rst_cnt <= 18'd0;
            cam_rst_n   <= 1'b0;
        end else if (cam_rst_cnt < 18'd200_000) begin
            cam_rst_cnt <= cam_rst_cnt + 18'd1;
            cam_rst_n   <= 1'b0;
        end else begin
            cam_rst_n   <= 1'b1;
        end
    end

    assign camera_reset = cam_rst_n;

    // ============================================================
    // SCCB camera config
    // IMPORTANT:
    // ov7670_config.v must configure the camera as real VGA 640x480.
    // If your config still uses QVGA, this top will not become real 640x480.
    // ============================================================
    ov7670_config camera_config (
        .clk(clk),
        .reset(reset || !clk_locked || !cam_rst_n),
        .sioc(camera_sioc),
        .siod(camera_siod),
        .config_done(config_done)
    );

    // ============================================================
    // OV7670 capture as 640-pixel line stream
    // ============================================================
    ov7670_capture_line #(
        .FRAME_WIDTH(640),
        .FRAME_HEIGHT(480)
    ) camera_capture (
        .pclk(camera_pclk),
        .reset(reset || !config_done),

        .vsync(camera_vsync),
        .href(camera_href),
        .data_in(camera_data),

        .byte_swap(byte_swap),
        .pclk_invert(pclk_invert),

        .pixel_x(cam_x),
        .pixel_y(cam_y),
        .line_addr(line_addr),
        .line_pixel(line_pixel),
        .line_we(line_we),

        .frame_active(frame_active),
        .new_frame_pulse(new_frame_pulse),
        .new_line_pulse(new_line_pulse)
    );

    // ============================================================
    // 2-line ping-pong buffer
    // ============================================================
    line_buffer_640 line_buffer (
        // Camera write side
        .wr_clk(camera_pclk),
        .wr_en(line_we),
        .wr_x(line_addr),
        .wr_y(cam_y),
        .wr_pixel(line_pixel),

        // VGA read side
        .rd_clk(clk_25mhz),
        .rd_x(vga_x_next),
        .rd_y(vga_y_next),
        .rd_pixel(buffer_pixel)
    );

    // ============================================================
    // VGA 640x480 controller
    // ============================================================
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

    // ============================================================
    // Image filter
    // ============================================================
    image_filter filter (
        .pixel_in(buffer_pixel),
        .filter_sel(filter_sel),
        .pixel_out(filtered_pixel)
    );

    assign vga_red   = vga_active ? filtered_pixel[11:8] : 4'b0000;
    assign vga_green = vga_active ? filtered_pixel[7:4]  : 4'b0000;
    assign vga_blue  = vga_active ? filtered_pixel[3:0]  : 4'b0000;

    // ============================================================
    // Debug LEDs
    // ============================================================
    reg [23:0] pclk_counter;
    always @(posedge camera_pclk or posedge reset) begin
        if (reset) begin
            pclk_counter <= 24'd0;
        end else begin
            pclk_counter <= pclk_counter + 24'd1;
        end
    end

    assign led[0] = config_done;
    assign led[1] = frame_active;
    assign led[2] = camera_href;
    assign led[3] = line_we;
    assign led[4] = new_frame_pulse;
    assign led[5] = new_line_pulse;
    assign led[6] = pclk_counter[23];
    assign led[7] = clk_locked;

endmodule