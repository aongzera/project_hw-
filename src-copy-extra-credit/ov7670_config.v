`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OV7670 SCCB Configuration Module (VGA 640x480 Version)
//////////////////////////////////////////////////////////////////////////////////

module ov7670_config(
    input  wire clk,           // 100 MHz
    input  wire reset,
    output wire sioc,          // SCCB clock (SCL)
    inout  wire siod,          // SCCB data (SDA)
    output reg  config_done    // High when full table sent
);
    parameter SCL_PERIOD      = 1000;
    parameter SCL_HALF        = SCL_PERIOD / 2;
    parameter POST_RESET_WAIT = 200_000;
    parameter INTER_MSG_WAIT  = 2_000;
    parameter CAM_ADDR        = 8'h42;
    parameter REG_COUNT       = 7'd30;

    reg [9:0] phase_cnt;
    always @(posedge clk or posedge reset) begin
        if (reset) phase_cnt <= 10'd0;
        else if (phase_cnt >= SCL_PERIOD - 1) phase_cnt <= 10'd0;
        else phase_cnt <= phase_cnt + 10'd1;
    end

    assign sioc = (phase_cnt >= SCL_HALF);
    wire tick_a = (phase_cnt == 10'd0);
    wire tick_b = (phase_cnt == SCL_HALF);

    reg sda_out;
    reg sda_oe;
    // Correct Open-Drain implementation: 
    // Drive 0 when sda_out is 0, else release to high-impedance (rely on pull-up)
    assign siod = (sda_oe && (sda_out == 1'b0)) ? 1'b0 : 1'bz;

    reg [15:0] config_regs [0:29];
    initial begin
        config_regs[ 0] = 16'h12_80; // COM7: Soft Reset
        config_regs[ 1] = 16'h12_04; // COM7: VGA Selection, RGB output
        config_regs[ 2] = 16'h11_00; // CLKRC: Prescaler (Direct)
        config_regs[ 3] = 16'h0C_00; // COM3: Disable DCW (Needed for Full VGA)
        config_regs[ 4] = 16'h3E_00; // COM14: No manual scaling
        config_regs[ 5] = 16'h8C_00; // RGB444 disable (Using RGB565)
        config_regs[ 6] = 16'h04_00; // COM1
        config_regs[ 7] = 16'h40_D0; // COM15: RGB565 + Full Range
        config_regs[ 8] = 16'h3A_04; // TSLB
        config_regs[ 9] = 16'h14_18; // COM9: AGC ceiling
        config_regs[10] = 16'h4F_B3; // MTX1
        config_regs[11] = 16'h50_B3; // MTX2
        config_regs[12] = 16'h51_00; // MTX3
        config_regs[13] = 16'h52_3D; // MTX4
        config_regs[14] = 16'h53_A7; // MTX5
        config_regs[15] = 16'h54_E4; // MTX6
        config_regs[16] = 16'h58_9E; // MTXS
        config_regs[17] = 16'h3D_80; // COM13: Disable UV Swap (Fixes Purple Tint)
        config_regs[18] = 16'h17_11; // HSTART
        config_regs[19] = 16'h18_61; // HSTOP
        config_regs[20] = 16'h32_A4; // HREF
        config_regs[21] = 16'h19_03; // VSTART
        config_regs[22] = 16'h1A_7B; // VSTOP
        config_regs[23] = 16'h03_0A; // VREF
        config_regs[24] = 16'h0E_61; // COM5
        config_regs[25] = 16'h0F_4B; // COM6
        config_regs[26] = 16'h16_02; // Reserved
        config_regs[27] = 16'h1E_07; // MVFP: Mirror/VFlip
        config_regs[28] = 16'h21_02; // ADCCTR1
        config_regs[29] = 16'h22_91; // ADCCTR2
    end

    localparam S_INIT_PAUSE = 4'd0, S_LOAD = 4'd1, S_START = 4'd2, 
               S_BIT_LOAD = 4'd3, S_BIT_HOLD = 4'd4, S_ACK = 4'd5, 
               S_STOP = 4'd7, S_WAIT = 4'd8, S_DONE = 4'd9;

    reg [3:0]  state;
    reg [6:0]  reg_idx;
    reg [3:0]  bit_cnt;
    reg [1:0]  byte_cnt;
    reg [23:0] tx_shift;
    reg [17:0] wait_cnt;
    reg        long_wait;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_INIT_PAUSE; reg_idx <= 0; bit_cnt <= 0;
            byte_cnt <= 0; tx_shift <= 0; sda_out <= 1; sda_oe <= 1;
            config_done <= 0; wait_cnt <= 0; long_wait <= 0;
        end else begin
            case (state)
                S_INIT_PAUSE: begin
                    sda_out <= 1; sda_oe <= 1;
                    if (wait_cnt >= POST_RESET_WAIT - 1) begin
                        wait_cnt <= 0; state <= S_LOAD;
                    end else wait_cnt <= wait_cnt + 1;
                end
                S_LOAD: begin
                    if (reg_idx >= REG_COUNT) state <= S_DONE;
                    else begin
                        tx_shift <= {CAM_ADDR, config_regs[reg_idx]};
                        bit_cnt <= 0; byte_cnt <= 0; sda_out <= 1;
                        sda_oe <= 1; state <= S_START;
                    end
                end
                S_START: if (tick_b) begin sda_out <= 0; state <= S_BIT_LOAD; end
                S_BIT_LOAD: if (tick_a) begin
                    sda_oe <= 1; sda_out <= tx_shift[23];
                    tx_shift <= {tx_shift[22:0], 1'b0};
                    bit_cnt <= 4'd1; state <= S_BIT_HOLD;
                end
                S_BIT_HOLD: if (tick_a) begin
                    if (bit_cnt == 4'd8) begin sda_oe <= 0; state <= S_ACK; end
                    else begin
                        sda_out <= tx_shift[23];
                        tx_shift <= {tx_shift[22:0], 1'b0};
                        bit_cnt <= bit_cnt + 1;
                    end
                end
                S_ACK: if (tick_a) begin
                    if (byte_cnt == 2'd2) begin sda_oe <= 1; sda_out <= 0; state <= S_STOP; end
                    else begin
                        sda_oe <= 1; sda_out <= tx_shift[23];
                        tx_shift <= {tx_shift[22:0], 1'b0};
                        bit_cnt <= 1; byte_cnt <= byte_cnt + 1; state <= S_BIT_HOLD;
                    end
                end
                S_STOP: if (tick_b) begin
                    sda_out <= 1; long_wait <= (reg_idx == 0);
                    wait_cnt <= 0; state <= S_WAIT;
                end
                S_WAIT: begin
                    if ((long_wait && wait_cnt >= POST_RESET_WAIT - 1) ||
                        (!long_wait && wait_cnt >= INTER_MSG_WAIT - 1)) begin
                        reg_idx <= reg_idx + 1; state <= S_LOAD;
                    end else wait_cnt <= wait_cnt + 1;
                end
                S_DONE: begin config_done <= 1; sda_oe <= 0; end
                default: state <= S_INIT_PAUSE;
            endcase
        end
    end
endmodule
