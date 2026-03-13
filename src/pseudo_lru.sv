// SPDX-License-Identifier: MIT
// pseudo-lru replacement tree
// 4-way, 64 sets
//
//          tree[0]          (root: left=ways{0,1}, right=ways{2,3})
//          /    \
//      tree[1]  tree[2]     (children)
//       / \      / \
//      W0  W1   W2  W3
//
// On ACCESS: bits updated to point AWAY from accessed way (marks MRU).
// VICTIM:    walk tree following bit values → points to LRU way.
// victim_way is registered (1-cycle latency from access_index).

`default_nettype none

module pseudo_lru #(
    parameter INDEX_W  = 6,
    parameter NUM_SETS = 64
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic              access_en,
    input  logic [INDEX_W-1:0] access_index,
    input  logic [1:0]        access_way,
    output logic [1:0]        victim_way
);

    // 3 bits per set, 64 sets
    logic [2:0] tree [NUM_SETS];

    // victim selection (comb, then registered)
    logic [1:0] victim_way_next;

    always_comb begin
        logic [2:0] bits;
        bits = tree[access_index];
        if (!bits[0])
            victim_way_next = bits[1] ? 2'd1 : 2'd0;
        else
            victim_way_next = bits[2] ? 2'd3 : 2'd2;
    end

    // sequential: register victim and update tree
    // note: victim_way lags 1 cycle from actual state. this is fine because we enter miss_select 1 cycle after lookup index is stable.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            victim_way <= 2'd0;
            for (int i = 0; i < NUM_SETS; i++)
                tree[i] <= 3'b000;
        end else begin
            victim_way <= victim_way_next;

            if (access_en) begin
                unique case (access_way)
                    2'd0: begin tree[access_index][0] <= 1'b1; tree[access_index][1] <= 1'b1; end
                    2'd1: begin tree[access_index][0] <= 1'b1; tree[access_index][1] <= 1'b0; end
                    2'd2: begin tree[access_index][0] <= 1'b0; tree[access_index][2] <= 1'b1; end
                    2'd3: begin tree[access_index][0] <= 1'b0; tree[access_index][2] <= 1'b0; end
                endcase
            end
        end
    end

endmodule
