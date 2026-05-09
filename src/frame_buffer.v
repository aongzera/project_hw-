`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Frame Buffer Module (Dual-Port Block RAM) - Upgraded to Full VGA 640x480
// 
// This is a wrapper for Vivado Block Memory Generator IP
// Configuration:
// - Memory Type: True Dual Port RAM
// - Port A Width: 3 bits (3-bit RGB to save BRAM) *** เปลี่ยนเป็น 3 บิต
// - Port A Depth: 307200 (640x480)                *** เปลี่ยนเป็น 307200
// - Port B Width: 3 bits                          *** เปลี่ยนเป็น 3 บิต
// - Port B Depth: 307200                          *** เปลี่ยนเป็น 307200
// - Enable Port Type: Always Enabled
// - Operating Mode: Write First
// 
// TO CREATE IN VIVADO (If using IP Core instead of behavioral):
// 1. IP Catalog -> Memories & Storage Elements -> Block Memory Generator
// 2. Configure as True Dual Port RAM
// 3. Set both ports to 3 bits width, 307200 depth (requires 19-bit addressing)
// 4. Generate the IP core
//////////////////////////////////////////////////////////////////////////////////

// Behavioral model for Synthesis / Simulation
module frame_buffer(
    // Port A (Write - Camera side)
    input wire clka,
    input wire wea,
    input wire [18:0] addra,    // 19 bits for 307200 addresses *** 19 บิต
    input wire [2:0] dina,      // 3 bits for color *** 3 บิต
    
    // Port B (Read - VGA side)
    input wire clkb,
    input wire [18:0] addrb,    // 19 bits *** 19 บิต
    output reg [2:0] doutb      // 3 bits *** 3 บิต
);

    // Block RAM storage (3-bit width, 307200 depth)
    (* ram_style = "block" *) reg [2:0] ram [0:307199];
    
    // Initialize RAM to black
    integer i;
    initial begin
        for (i = 0; i < 307200; i = i + 1) begin
            ram[i] = 3'b000;
        end
    end
    
    // Port A: Write operation
    always @(posedge clka) begin
        if (wea) begin
            ram[addra] <= dina;
        end
    end
    
    // Port B: Read operation
    always @(posedge clkb) begin
        doutb <= ram[addrb];
    end

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Alternative: Use Vivado Block Memory Generator IP
// 
// Uncomment this section and comment out the behavioral model above
// after generating the IP core in Vivado (Make sure it matches 3-bit, 307200 depth)
//////////////////////////////////////////////////////////////////////////////////

/*
module frame_buffer(
    input wire clka,
    input wire wea,
    input wire [18:0] addra,
    input wire [2:0] dina,
    input wire clkb,
    input wire [18:0] addrb,
    output wire [2:0] doutb
);

    blk_mem_gen_0 bram_inst (
        .clka(clka),
        .wea(wea),
        .addra(addra),
        .dina(dina),
        .clkb(clkb),
        .addrb(addrb),
        .doutb(doutb)
    );

endmodule
*/