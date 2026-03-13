// SPDX-License-Identifier: MIT
// sky130 sram macro blackbox for synthesis
// sky130_sram_1kbyte_1rw1r_32x256_8
// this module is blackboxed and replaced during pnr

`default_nettype none

module sky130_sram_1kbyte_1rw1r_32x256_8 (
    // port 0: rw
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire [7:0]  addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0,
    // port 1: r
    input  wire        clk1,
    input  wire        csb1,
    input  wire [7:0]  addr1,
    output wire [31:0] dout1
);

    // blackbox - no implementation for synthesis.
    // yosys defines SYNTHESIS automatically; the behavioral model
    // below is only compiled for simulation.

`ifndef SYNTHESIS
    // simple behavioral model for sim only
    reg [31:0] mem [0:255];
    reg [31:0] dout0_reg;
    reg [31:0] dout1_reg;

    assign dout0 = dout0_reg;
    assign dout1 = dout1_reg;

    always @(posedge clk0) begin
        if (!csb0) begin
            if (!web0) begin
                if (wmask0[0]) mem[addr0][ 7: 0] <= din0[ 7: 0];
                if (wmask0[1]) mem[addr0][15: 8] <= din0[15: 8];
                if (wmask0[2]) mem[addr0][23:16] <= din0[23:16];
                if (wmask0[3]) mem[addr0][31:24] <= din0[31:24];
            end
            dout0_reg <= mem[addr0];
        end
    end

    always @(posedge clk1) begin
        if (!csb1) begin
            dout1_reg <= mem[addr1];
        end
    end
`endif

endmodule
