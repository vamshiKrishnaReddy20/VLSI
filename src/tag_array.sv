// SPDX-License-Identifier: MIT
// tag array definition
// register based, 64 sets, 22-bit tag per way
// one instance per way
// combinational read, sequential write

`default_nettype none

module tag_array #(
    parameter INDEX_W = 6,
    parameter TAG_W   = 22,
    parameter NUM_SETS= 64
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic              we,
    input  logic [INDEX_W-1:0] index,
    input  logic [TAG_W-1:0]  tag_in,
    output logic [TAG_W-1:0]  tag_out
);

    // 64-entry regfile
    logic [TAG_W-1:0] mem [NUM_SETS];

    // comb read
    assign tag_out = mem[index];

    // seq write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SETS; i++)
                mem[i] <= '0;
        end else if (we) begin
            mem[index] <= tag_in;
        end
    end

endmodule
