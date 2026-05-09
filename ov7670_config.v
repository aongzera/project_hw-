`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OV7670 SCCB Configuration Module - FIXED VERSION
//
// Main fixes from the old version:
// 1) The camera is configured as RGB565, because ov7670_capture.v reads two
//    bytes as RGB565. The old table enabled RGB444, which does not match the
//    capture logic.
// 2) The SCCB transaction now has a real 9th ACK clock after every byte.
//    The old code released SDA for ACK but did not create a separate ACK bit
//    time, so many cameras would not accept the register writes reliably.
// 3) Adds a delay after COM7 reset (0x12 = 0x80). OV7670 needs time to reset
//    its internal registers before the next register write.
// 4) Uses open-drain style SDA: drive 0 for low, release Z for high/ACK.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_config #(
    parameter CLK_FREQ_HZ  = 100_000_000,
    parameter SCCB_FREQ_HZ = 100_000
)(
    input  wire clk,          // 100 MHz system clock
    input  wire reset,        // active high reset
    output reg  sioc,         // SCCB clock
    inout  wire siod,         // SCCB data
    output reg  config_done   // 1 when all registers have been sent
);

    // One SCCB bit uses 4 phases, so each phase tick is CLK/(SCCB*4).
    localparam integer TICK_DIV = CLK_FREQ_HZ / (SCCB_FREQ_HZ * 4);
    localparam integer NUM_REGS = 42;
    localparam integer RESET_DELAY_TICKS  = (SCCB_FREQ_HZ * 4) / 100; // 10 ms in phase ticks

    localparam [7:0] CAM_ADDR_WR = 8'h42; // OV7670 SCCB write address

    // Top-level transaction states
    localparam ST_POWERUP_DELAY = 4'd0;
    localparam ST_LOAD          = 4'd1;
    localparam ST_START_1       = 4'd2;
    localparam ST_START_2       = 4'd3;
    localparam ST_START_3       = 4'd4;
    localparam ST_SEND_BYTE     = 4'd5;
    localparam ST_ACK           = 4'd6;
    localparam ST_STOP_1        = 4'd7;
    localparam ST_STOP_2        = 4'd8;
    localparam ST_STOP_3        = 4'd9;
    localparam ST_NEXT          = 4'd10;
    localparam ST_RESET_DELAY   = 4'd11;
    localparam ST_DONE          = 4'd12;

    // Which byte of one register transaction is being sent
    localparam BYTE_DEV  = 2'd0;
    localparam BYTE_REG  = 2'd1;
    localparam BYTE_DATA = 2'd2;

    reg [3:0]  state;
    reg [1:0]  byte_stage;
    reg [1:0]  bit_phase;
    reg [2:0]  bit_index;
    reg [7:0]  tx_byte;
    reg [7:0]  reg_index;
    reg [15:0] current_reg;
    reg [31:0] tick_count;
    reg [31:0] delay_count;

    reg sda_drive_low;

    // SCCB/I2C open-drain behavior: never drive a logic 1 on SDA.
    // The XDC enables an internal pull-up; an external 4.7k pull-up is better
    // if your camera module does not already have one.
    assign siod = sda_drive_low ? 1'b0 : 1'bz;

    wire [7:0] reg_addr = current_reg[15:8];
    wire [7:0] reg_data = current_reg[7:0];

    // Register table for QVGA RGB565 output.
    // This matches ov7670_capture.v, which expects RGB565 byte pairs.
    reg [15:0] config_regs [0:NUM_REGS-1];
    initial begin
        config_regs[0]  = 16'h12_80; // COM7: reset all registers

        // Output format and scaling
        config_regs[1]  = 16'h12_14; // COM7: QVGA + RGB output
        config_regs[2]  = 16'h11_01; // CLKRC: prescale internal clock slightly
        config_regs[3]  = 16'h0C_04; // COM3: enable scaling/DCW
        config_regs[4]  = 16'h3E_19; // COM14: QVGA scaling + PCLK divide
        config_regs[5]  = 16'h8C_00; // RGB444: disabled, use RGB565 instead
        config_regs[6]  = 16'h40_D0; // COM15: RGB565 + full 0-255 range
        config_regs[7]  = 16'h3A_04; // TSLB: correct RGB byte order for RGB565
        config_regs[8]  = 16'h3D_C0; // COM13: gamma/UV saturation enable

        // QVGA scaling registers
        config_regs[9]  = 16'h70_3A; // SCALING_XSC
        config_regs[10] = 16'h71_35; // SCALING_YSC
        config_regs[11] = 16'h72_11; // SCALING_DCWCTR
        config_regs[12] = 16'h73_F0; // SCALING_PCLK_DIV
        config_regs[13] = 16'hA2_02; // SCALING_PCLK_DELAY

        // Windowing/cropping
        config_regs[14] = 16'h17_16; // HSTART
        config_regs[15] = 16'h18_04; // HSTOP
        config_regs[16] = 16'h32_80; // HREF
        config_regs[17] = 16'h19_02; // VSTART
        config_regs[18] = 16'h1A_7A; // VSTOP
        config_regs[19] = 16'h03_0A; // VREF

        // Automatic exposure/gain/color control
        config_regs[20] = 16'h13_E7; // COM8: AGC/AEC/AWB enable
        config_regs[21] = 16'h00_00; // GAIN
        config_regs[22] = 16'h10_00; // AECH
        config_regs[23] = 16'h0D_40; // COM4
        config_regs[24] = 16'h14_38; // COM9: gain ceiling
        config_regs[25] = 16'hA5_05; // BD50MAX
        config_regs[26] = 16'hAB_07; // BD60MAX
        config_regs[27] = 16'h24_95; // AEW
        config_regs[28] = 16'h25_33; // AEB
        config_regs[29] = 16'h26_E3; // VPT
        config_regs[30] = 16'h9F_78; // HAECC1
        config_regs[31] = 16'hA0_68; // HAECC2
        config_regs[32] = 16'hA1_03; // reserved/AEC
        config_regs[33] = 16'hA6_D8; // HAECC3
        config_regs[34] = 16'hA7_D8; // HAECC4
        config_regs[35] = 16'hA8_F0; // HAECC5
        config_regs[36] = 16'hA9_90; // HAECC6
        config_regs[37] = 16'hAA_94; // HAECC7
        config_regs[38] = 16'h13_E7; // COM8 again after AEC setup

        // Color matrix for RGB output
        config_regs[39] = 16'h4F_B3; // MTX1
        config_regs[40] = 16'h50_B3; // MTX2
        config_regs[41] = 16'h51_00; // MTX3
    end

    wire tick = (tick_count == TICK_DIV - 1);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tick_count <= 32'd0;
        end else if (tick) begin
            tick_count <= 32'd0;
        end else begin
            tick_count <= tick_count + 32'd1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= ST_POWERUP_DELAY;
            reg_index     <= 8'd0;
            current_reg   <= 16'd0;
            byte_stage    <= BYTE_DEV;
            bit_phase     <= 2'd0;
            bit_index     <= 3'd7;
            tx_byte       <= 8'd0;
            delay_count   <= 32'd0;
            sioc          <= 1'b1;
            sda_drive_low <= 1'b0; // released/high
            config_done   <= 1'b0;
        end else if (tick) begin
            case (state)
                ST_POWERUP_DELAY: begin
                    // Let XCLK and the sensor settle before SCCB writes.
                    sioc          <= 1'b1;
                    sda_drive_low <= 1'b0;
                    config_done   <= 1'b0;
                    if (delay_count >= RESET_DELAY_TICKS) begin
                        delay_count <= 32'd0;
                        state       <= ST_LOAD;
                    end else begin
                        delay_count <= delay_count + 32'd1;
                    end
                end

                ST_LOAD: begin
                    if (reg_index < NUM_REGS) begin
                        current_reg <= config_regs[reg_index];
                        byte_stage  <= BYTE_DEV;
                        tx_byte     <= CAM_ADDR_WR;
                        bit_index   <= 3'd7;
                        bit_phase   <= 2'd0;
                        state       <= ST_START_1;
                    end else begin
                        state <= ST_DONE;
                    end
                end

                // START: SDA goes low while SCL is high, then pull SCL low.
                ST_START_1: begin
                    sioc          <= 1'b1;
                    sda_drive_low <= 1'b0;
                    state         <= ST_START_2;
                end

                ST_START_2: begin
                    sioc          <= 1'b1;
                    sda_drive_low <= 1'b1;
                    state         <= ST_START_3;
                end

                ST_START_3: begin
                    sioc      <= 1'b0;
                    bit_phase <= 2'd0;
                    bit_index <= 3'd7;
                    state     <= ST_SEND_BYTE;
                end

                ST_SEND_BYTE: begin
                    case (bit_phase)
                        2'd0: begin
                            // SCL low: set SDA for this bit.
                            sioc          <= 1'b0;
                            sda_drive_low <= (tx_byte[bit_index] == 1'b0);
                            bit_phase     <= 2'd1;
                        end

                        2'd1: begin
                            // Keep setup time before SCL rises.
                            sioc      <= 1'b0;
                            bit_phase <= 2'd2;
                        end

                        2'd2: begin
                            // SCL high: camera samples the bit.
                            sioc      <= 1'b1;
                            bit_phase <= 2'd3;
                        end

                        2'd3: begin
                            sioc <= 1'b0;
                            if (bit_index == 3'd0) begin
                                bit_phase <= 2'd0;
                                state     <= ST_ACK;
                            end else begin
                                bit_index <= bit_index - 3'd1;
                                bit_phase <= 2'd0;
                            end
                        end
                    endcase
                end

                ST_ACK: begin
                    case (bit_phase)
                        2'd0: begin
                            // 9th clock: release SDA so camera can ACK.
                            sioc          <= 1'b0;
                            sda_drive_low <= 1'b0;
                            bit_phase     <= 2'd1;
                        end

                        2'd1: begin
                            sioc      <= 1'b0;
                            bit_phase <= 2'd2;
                        end

                        2'd2: begin
                            sioc      <= 1'b1;
                            bit_phase <= 2'd3;
                            // We do not fail on NACK because some modules do
                            // not expose clean ACK, but the clock is still valid.
                        end

                        2'd3: begin
                            sioc      <= 1'b0;
                            bit_phase <= 2'd0;
                            bit_index <= 3'd7;

                            if (byte_stage == BYTE_DEV) begin
                                byte_stage <= BYTE_REG;
                                tx_byte    <= reg_addr;
                                state      <= ST_SEND_BYTE;
                            end else if (byte_stage == BYTE_REG) begin
                                byte_stage <= BYTE_DATA;
                                tx_byte    <= reg_data;
                                state      <= ST_SEND_BYTE;
                            end else begin
                                state <= ST_STOP_1;
                            end
                        end
                    endcase
                end

                // STOP: SDA rises while SCL is high.
                ST_STOP_1: begin
                    sioc          <= 1'b0;
                    sda_drive_low <= 1'b1;
                    state         <= ST_STOP_2;
                end

                ST_STOP_2: begin
                    sioc          <= 1'b1;
                    sda_drive_low <= 1'b1;
                    state         <= ST_STOP_3;
                end

                ST_STOP_3: begin
                    sioc          <= 1'b1;
                    sda_drive_low <= 1'b0;
                    state         <= ST_NEXT;
                end

                ST_NEXT: begin
                    if (reg_index == 8'd0) begin
                        // After COM7 reset, wait before sending the rest.
                        delay_count <= 32'd0;
                        reg_index   <= reg_index + 8'd1;
                        state       <= ST_RESET_DELAY;
                    end else begin
                        reg_index <= reg_index + 8'd1;
                        state     <= ST_LOAD;
                    end
                end

                ST_RESET_DELAY: begin
                    sioc          <= 1'b1;
                    sda_drive_low <= 1'b0;

                    if (delay_count >= RESET_DELAY_TICKS) begin
                        delay_count <= 32'd0;
                        state       <= ST_LOAD;
                    end else begin
                        delay_count <= delay_count + 32'd1;
                    end
                end

                ST_DONE: begin
                    sioc          <= 1'b1;
                    sda_drive_low <= 1'b0;
                    config_done   <= 1'b1;
                end

                default: begin
                    state <= ST_POWERUP_DELAY;
                end
            endcase
        end
    end

endmodule