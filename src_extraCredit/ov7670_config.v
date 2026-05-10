`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OV7670 SCCB Configuration Module (rewritten)
//
// Implements an SCCB (I2C-like) master correctly:
//   - SDA changes happen ONLY while SCL is low (data bits).
//   - START is generated as SDA falling while SCL is high.
//   - STOP  is generated as SDA rising  while SCL is high.
//   - 9th "don't care" bit per byte: master releases SDA (sda_oe=0).
//   - 2 ms wait after writing the COM7 soft-reset (datasheet requires >=1 ms).
//
// SCL phase:
//   phase_cnt counts 0..SCL_PERIOD-1 within one SCL bit period.
//   SCL is low while phase_cnt < SCL_HALF, high otherwise.
//   tick_a fires at the start of SCL low phase  -> safe time to change SDA.
//   tick_b fires at the start of SCL high phase -> time to issue START / STOP.
//
// Each SCCB write transmits 3 bytes:
//   { slave_addr=8'h42 , reg_addr , reg_data }
// followed by START at the beginning and STOP at the end.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_config(
    input  wire clk,           // 100 MHz
    input  wire reset,
    output wire sioc,          // SCCB clock (SCL)
    inout  wire siod,          // SCCB data  (SDA, open-drain via tristate)
    output reg  config_done    // High when full table sent
);

    // SCCB bit period: 100 MHz / 1000 = 100 kHz (well below the 400 kHz max)
    parameter SCL_PERIOD      = 1000;
    parameter SCL_HALF        = SCL_PERIOD / 2;
    parameter POST_RESET_WAIT = 200_000;   // 2 ms at 100 MHz
    parameter INTER_MSG_WAIT  = 2_000;     // 20 us between writes
    parameter CAM_ADDR        = 8'h42;     // OV7670 write address
    parameter REG_COUNT       = 7'd30;

    //--------------------------------------------------------------------------
    // SCL phase counter
    //--------------------------------------------------------------------------
    reg [9:0] phase_cnt;

    always @(posedge clk or posedge reset) begin
        if (reset)
            phase_cnt <= 10'd0;
        else if (phase_cnt >= SCL_PERIOD - 1)
            phase_cnt <= 10'd0;
        else
            phase_cnt <= phase_cnt + 10'd1;
    end

    assign sioc = (phase_cnt >= SCL_HALF);   // low first half, high second half

    wire tick_a = (phase_cnt == 10'd0);           // SCL just went low
    wire tick_b = (phase_cnt == SCL_HALF);        // SCL just went high

    //--------------------------------------------------------------------------
    // SDA tristate
    //--------------------------------------------------------------------------
    reg sda_out;
    reg sda_oe;
    assign siod = (sda_oe && (sda_out == 1'b0)) ? 1'b0 : 1'bz;

    //--------------------------------------------------------------------------
    // Configuration table — minimal QVGA/RGB565 init that relies on the
    // OV7670's defaults for scaling instead of explicitly programming the
    // SCALING_* registers (those were giving us a tiny top-left image because
    // the values aren't right for every silicon rev).
    //
    // COM7 bit 4 (QVGA) does the downsampling on its own on most modules.
    //--------------------------------------------------------------------------
    reg [15:0] config_regs [0:29];

    initial begin
        config_regs[ 0] = 16'h12_80;  // COM7  : soft reset (followed by long wait)
        config_regs[ 1] = 16'h12_04;  // COM7  : VGA + RGB output, no QVGA
        config_regs[ 2] = 16'h11_00;  // CLKRC : external clock directly
        config_regs[ 3] = 16'h0C_00;  // COM3  : disable DCW / downsampling
        config_regs[ 4] = 16'h3E_00;  // COM14 : no manual scaling
        config_regs[ 5] = 16'h8C_00;  // RGB444 disable (we use RGB565)
        config_regs[ 6] = 16'h04_00;  // COM1
        config_regs[ 7] = 16'h40_D0;  // COM15 : RGB565 + full output range
        config_regs[ 8] = 16'h3A_04;  // TSLB
        config_regs[ 9] = 16'h14_18;  // COM9  : AGC ceiling
        config_regs[10] = 16'h4F_B3;  // MTX1
        config_regs[11] = 16'h50_B3;  // MTX2
        config_regs[12] = 16'h51_00;  // MTX3
        config_regs[13] = 16'h52_3D;  // MTX4
        config_regs[14] = 16'h53_A7;  // MTX5
        config_regs[15] = 16'h54_E4;  // MTX6
        config_regs[16] = 16'h58_9E;  // MTXS
        config_regs[17] = 16'h3D_C0;  // COM13
        config_regs[18] = 16'h17_13;  // HSTART
        config_regs[19] = 16'h18_01;  // HSTOP
        config_regs[20] = 16'h32_B6;  // HREF
        config_regs[21] = 16'h19_02;  // VSTART
        config_regs[22] = 16'h1A_7B;  // VSTOP
        config_regs[23] = 16'h03_0A;  // VREF
        config_regs[24] = 16'h0E_61;  // COM5
        config_regs[25] = 16'h0F_4B;  // COM6
        config_regs[26] = 16'h16_02;  // Reserved
        config_regs[27] = 16'h1E_07;  // MVFP : mirror / vflip
        config_regs[28] = 16'h21_02;  // ADCCTR1
        config_regs[29] = 16'h22_91;  // ADCCTR2
    end

    //--------------------------------------------------------------------------
    // Main FSM
    //--------------------------------------------------------------------------
    localparam S_INIT_PAUSE = 4'd0;   // Hold bus idle after reset
    localparam S_LOAD       = 4'd1;   // Load next register, wait to issue START
    localparam S_START      = 4'd2;   // SDA falls while SCL high
    localparam S_BIT_LOAD   = 4'd3;   // First data bit of a byte
    localparam S_BIT_HOLD   = 4'd4;   // Subsequent data bits + boundary check
    localparam S_ACK        = 4'd5;   // Master releases SDA for don't-care bit
    localparam S_STOP_PREP  = 4'd6;   // Drive SDA low while SCL low
    localparam S_STOP       = 4'd7;   // SDA rises while SCL high
    localparam S_WAIT       = 4'd8;   // Inter-write or post-reset wait
    localparam S_DONE       = 4'd9;

    reg [3:0]  state;
    reg [6:0]  reg_idx;
    reg [3:0]  bit_cnt;        // 0..7 within a byte
    reg [1:0]  byte_cnt;       // 0..2 across the 3 bytes of one write
    reg [23:0] tx_shift;
    reg [17:0] wait_cnt;
    reg        long_wait;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= S_INIT_PAUSE;
            reg_idx     <= 7'd0;
            bit_cnt     <= 4'd0;
            byte_cnt    <= 2'd0;
            tx_shift    <= 24'd0;
            sda_out     <= 1'b1;
            sda_oe      <= 1'b1;       // drive idle high so SDA isn't floating
            config_done <= 1'b0;
            wait_cnt    <= 18'd0;
            long_wait   <= 1'b0;
        end else begin
            case (state)

                // -----------------------------------------------------------
                // Power-on idle: hold SDA / SCL high for ~2 ms before talking.
                // -----------------------------------------------------------
                S_INIT_PAUSE: begin
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b1;
                    if (wait_cnt >= POST_RESET_WAIT - 1) begin
                        wait_cnt <= 18'd0;
                        state    <= S_LOAD;
                    end else begin
                        wait_cnt <= wait_cnt + 18'd1;
                    end
                end

                // -----------------------------------------------------------
                // Pull next register from the table.  When all sent -> DONE.
                // -----------------------------------------------------------
                S_LOAD: begin
                    if (reg_idx >= REG_COUNT) begin
                        state <= S_DONE;
                    end else begin
                        tx_shift <= { CAM_ADDR,
                                      config_regs[reg_idx][15:8],
                                      config_regs[reg_idx][7:0] };
                        bit_cnt  <= 4'd0;
                        byte_cnt <= 2'd0;
                        sda_out  <= 1'b1;
                        sda_oe   <= 1'b1;
                        state    <= S_START;
                    end
                end

                // -----------------------------------------------------------
                // START: at tick_b SDA falls while SCL is high.
                // -----------------------------------------------------------
                S_START: begin
                    if (tick_b) begin
                        sda_out <= 1'b0;
                        state   <= S_BIT_LOAD;
                    end
                end

                // -----------------------------------------------------------
                // Send the FIRST bit of a byte (MSB) when SCL goes low again.
                // -----------------------------------------------------------
                S_BIT_LOAD: begin
                    if (tick_a) begin
                        sda_oe   <= 1'b1;
                        sda_out  <= tx_shift[23];
                        tx_shift <= { tx_shift[22:0], 1'b0 };
                        bit_cnt  <= 4'd1;
                        state    <= S_BIT_HOLD;
                    end
                end

                // -----------------------------------------------------------
                // Send remaining bits, then release SDA for the don't-care bit.
                // -----------------------------------------------------------
                S_BIT_HOLD: begin
                    if (tick_a) begin
                        if (bit_cnt == 4'd8) begin
                            // 8 bits sent.  Release SDA for don't-care/ACK bit.
                            sda_oe  <= 1'b0;
                            state   <= S_ACK;
                        end else begin
                            sda_out  <= tx_shift[23];
                            tx_shift <= { tx_shift[22:0], 1'b0 };
                            bit_cnt  <= bit_cnt + 4'd1;
                        end
                    end
                end

                // -----------------------------------------------------------
                // Don't-care / ACK cycle: one full SCL period with SDA released.
                // After it, either start the next byte or move to STOP.
                // -----------------------------------------------------------
                S_ACK: begin
                    if (tick_a) begin
                        if (byte_cnt == 2'd2) begin
                            // Last byte done -> prepare STOP
                            sda_oe  <= 1'b1;
                            sda_out <= 1'b0;        // pre-stop: SDA low while SCL low
                            state   <= S_STOP;
                        end else begin
                            // Start next byte: send its MSB now
                            sda_oe   <= 1'b1;
                            sda_out  <= tx_shift[23];
                            tx_shift <= { tx_shift[22:0], 1'b0 };
                            bit_cnt  <= 4'd1;
                            byte_cnt <= byte_cnt + 2'd1;
                            state    <= S_BIT_HOLD;
                        end
                    end
                end

                // -----------------------------------------------------------
                // STOP: at tick_b SDA rises while SCL is high.
                // After STOP, wait long if we just sent COM7 reset, else short.
                // -----------------------------------------------------------
                S_STOP: begin
                    if (tick_b) begin
                        sda_out   <= 1'b1;
                        long_wait <= (reg_idx == 7'd0);
                        wait_cnt  <= 18'd0;
                        state     <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if ( ( long_wait && wait_cnt >= POST_RESET_WAIT - 1) ||
                         (!long_wait && wait_cnt >= INTER_MSG_WAIT  - 1) ) begin
                        reg_idx <= reg_idx + 7'd1;
                        state   <= S_LOAD;
                    end else begin
                        wait_cnt <= wait_cnt + 18'd1;
                    end
                end

                S_DONE: begin
                    config_done <= 1'b1;
                    sda_oe      <= 1'b0;     // release the bus
                end

                default: state <= S_INIT_PAUSE;
            endcase
        end
    end

endmodule
