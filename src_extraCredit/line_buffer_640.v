`timescale 1ns / 1ps

module line_buffer_640(
    // Camera write side
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [9:0]  wr_x,
    input  wire [9:0]  wr_y,
    input  wire [11:0] wr_pixel,

    // VGA read side
    input  wire        rd_clk,
    input  wire [9:0]  rd_x,
    input  wire [9:0]  rd_y,
    output reg  [11:0] rd_pixel
);

    (* ram_style = "block" *) reg [11:0] line0 [0:639];
    (* ram_style = "block" *) reg [11:0] line1 [0:639];

    wire wr_line_sel = wr_y[0];
    wire rd_line_sel = rd_y[0];

    // Write port: camera PCLK domain
    always @(posedge wr_clk) begin
        if (wr_en && wr_x < 640) begin
            if (wr_line_sel == 1'b0) begin
                line0[wr_x] <= wr_pixel;
            end else begin
                line1[wr_x] <= wr_pixel;
            end
        end
    end

    // Read port: VGA pixel clock domain
    always @(posedge rd_clk) begin
        if (rd_x < 640) begin
            if (rd_line_sel == 1'b0) begin
                rd_pixel <= line0[rd_x];
            end else begin
                rd_pixel <= line1[rd_x];
            end
        end else begin
            rd_pixel <= 12'h000;
        end
    end

endmodule