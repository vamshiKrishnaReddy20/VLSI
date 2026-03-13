// SPDX-License-Identifier: MIT
// data array wrapper for sky130 sram macro
// one instance per way
// simplified interface mapping index and word_sel to an 8-bit sram addr
// sram is kept selected and we always do full-word writes

`default_nettype none

module data_array (
    input  logic              clk,
    input  logic              we,
    input  logic [5:0]        index,
    input  logic [1:0]        word_sel,
    input  logic [31:0]       wdata,
    output logic [31:0]       rdata
);

    // internal signals
    logic [7:0]   sram_addr;
    logic [31:0]  sram_dout;
    logic [31:0]            unused_dout1;

    // address mapping: {index[5:0], word_sel[1:0]}
    assign sram_addr = {index, word_sel};
    assign rdata     = sram_dout;

    // sky130 sram macro instance
    sky130_sram_1kbyte_1rw1r_32x256_8 sram_inst (
        // port 0: rw
        .clk0   (clk),
        .csb0   (1'b0),           // selected
        .web0   (~we),            // active low we
        .wmask0 (4'b1111),        // full word writes
        .addr0  (sram_addr),
        .din0   (wdata),
        .dout0  (sram_dout),
        // port 1: r (unused, tied off)
        .clk1   (clk),
        .csb1   (1'b1),           // disabled
        .addr1  (8'd0),
        .dout1  (unused_dout1)
    );

endmodule
