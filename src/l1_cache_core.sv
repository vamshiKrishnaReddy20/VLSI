// SPDX-License-Identifier: MIT
// l1 data cache core
// 4kb, 4-way set associative, 16-byte line, write-back/write-allocate
// architecture follows reference design using proper sv constructs

`default_nettype none

module l1_cache_core (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Request Interface
    input  wire        req_valid,
    input  wire        req_we,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wstrb,
    output logic       resp_valid,
    output logic [31:0] resp_rdata,
    output logic       resp_stall,

    // Memory Interface
    output logic       mem_req_valid,
    output logic       mem_req_we,
    output logic [31:0] mem_req_addr,
    output logic [31:0] mem_req_wdata,
    input  wire [31:0] mem_resp_rdata,
    input  wire        mem_resp_valid
);

    // local constants
    localparam int ADDR_W        = 32;
    localparam int DATA_W        = 32;
    localparam int NUM_SETS      = 64;
    localparam int NUM_WAYS      = 4;
    localparam int LINE_BYTES    = 16;
    localparam int WORDS_PER_LINE= 4;
    localparam int BYTE_OFF_W    = 2;
    localparam int WORD_OFF_W    = 2;
    localparam int INDEX_W       = 6;
    localparam int TAG_W         = 22;

    // fsm states
    typedef enum logic [2:0] {
        S_IDLE            = 3'd0,
        S_LOOKUP          = 3'd1,
        S_MISS_SELECT     = 3'd2,
        S_WRITEBACK_REQ   = 3'd3,
        S_WRITEBACK_WAIT  = 3'd4,
        S_REFILL_REQ      = 3'd5,
        S_REFILL_WAIT     = 3'd6,
        S_REFILL_COMPLETE = 3'd7
    } state_t;

    // internal signals
    state_t state;

    // Latched request
    logic [ADDR_W-1:0] cur_addr;
    logic              cur_we;
    logic [DATA_W-1:0] cur_wdata;
    logic [3:0]        cur_wstrb;

    // Extracted address fields (from latched address)
    logic [TAG_W-1:0]      cur_tag;
    logic [INDEX_W-1:0]    cur_index;
    logic [WORD_OFF_W-1:0] cur_word;

    assign cur_tag   = cur_addr[31:10];
    assign cur_index = cur_addr[9:4];
    assign cur_word  = cur_addr[3:2];

    // Valid / dirty — flat vectors, indexed by {set, way}
    logic [NUM_SETS*NUM_WAYS-1:0] valid_bits;
    logic [NUM_SETS*NUM_WAYS-1:0] dirty_bits;

    // flat index helper: {set, way} to 8-bit mapped
    function automatic logic [7:0] flat(input logic [INDEX_W-1:0] s, input logic [1:0] w);
        flat = {s, w};
    endfunction

    // Byte-mask from write strobe
    function automatic logic [31:0] strb_mask(input logic [3:0] s);
        strb_mask = {{8{s[3]}}, {8{s[2]}}, {8{s[1]}}, {8{s[0]}}};
    endfunction

    // array read buses
    logic [TAG_W-1:0]  tag_rd  [NUM_WAYS];
    logic [DATA_W-1:0] data_rd [NUM_WAYS];

    // array control signals
    logic              tag_we;
    logic [INDEX_W-1:0] tag_idx;
    logic [1:0]        tag_way;
    logic [TAG_W-1:0]  tag_wdata;

    logic              data_we;
    logic [INDEX_W-1:0] data_idx;
    logic [1:0]        data_way;
    logic [1:0]        data_wsel;
    logic [DATA_W-1:0] data_wdata;

    // tracking registers
    logic [1:0]   victim_way;
    logic [31:0]  victim_addr;
    logic [1:0]   xfer_cnt;
    logic [127:0] refill_buf;

    // array instantiations (one per way)
    for (genvar w = 0; w < NUM_WAYS; w++) begin : gen_way
        tag_array #(
            .INDEX_W(INDEX_W),
            .TAG_W(TAG_W),
            .NUM_SETS(NUM_SETS)
        ) u_tag (
            .clk     (clk),
            .rst_n   (rst_n),
            .we      (tag_we & (tag_way == w[1:0])),
            .index   (tag_idx),
            .tag_in  (tag_wdata),
            .tag_out (tag_rd[w])
        );

        data_array u_data (
            .clk      (clk),
            .we       (data_we & (data_way == 2'(w))),
            .index    (data_idx),
            .word_sel (data_wsel),
            .wdata    (data_wdata),
            .rdata    (data_rd[w])
        );
    end

    // hit detection
    logic [NUM_WAYS-1:0] way_hit;
    logic                hit_found;
    logic [1:0]          hit_way;

    always_comb begin
        for (int w = 0; w < NUM_WAYS; w++)
            way_hit[w] = valid_bits[flat(cur_index, 2'(w))] & (tag_rd[w] == cur_tag);
    end

    assign hit_found = |way_hit;

    always_comb begin
        priority case (1'b1)
            way_hit[0]: hit_way = 2'd0;
            way_hit[1]: hit_way = 2'd1;
            way_hit[2]: hit_way = 2'd2;
            default:    hit_way = 2'd3;
        endcase
    end

    // victim selection (prefer invalid, then plru)
    logic [1:0] plru_victim;
    logic [1:0] sel_victim;

    always_comb begin
        if      (!valid_bits[flat(cur_index, 2'd0)]) sel_victim = 2'd0;
        else if (!valid_bits[flat(cur_index, 2'd1)]) sel_victim = 2'd1;
        else if (!valid_bits[flat(cur_index, 2'd2)]) sel_victim = 2'd2;
        else if (!valid_bits[flat(cur_index, 2'd3)]) sel_victim = 2'd3;
        else                                         sel_victim = plru_victim;
    end

    // stall signal
    assign resp_stall = (state != S_IDLE);

    // plru instance
    logic       plru_update_en;
    logic [1:0] plru_access_way_comb;

    assign plru_update_en  = (state == S_LOOKUP && hit_found) ||
                             (state == S_REFILL_WAIT && mem_resp_valid && xfer_cnt == 2'd3);

    assign plru_access_way_comb = (state == S_REFILL_WAIT) ? victim_way : hit_way;

    pseudo_lru #(
        .INDEX_W(INDEX_W),
        .NUM_SETS(NUM_SETS)
    ) plru_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .access_en    (plru_update_en),
        .access_index (cur_index),
        .access_way   (plru_access_way_comb),
        .victim_way   (plru_victim)
    );

    // comb logic for sram control
    // tag array control
    always_comb begin
        tag_we    = 1'b0;
        tag_idx   = cur_index;
        tag_way   = 2'd0;
        tag_wdata = '0;

        unique case (state)
            S_IDLE: begin
                if (req_valid) tag_idx = req_addr[9:4];
            end
            S_REFILL_WAIT: begin
                if (mem_resp_valid && xfer_cnt == 2'd3) begin
                    tag_idx   = cur_index;
                    tag_way   = victim_way;
                    tag_wdata = cur_tag;
                    tag_we    = 1'b1;
                end
            end
            default: ;
        endcase
    end

    logic [31:0] refilled;
    // data array control
    always_comb begin
        refilled   = '0; // Default assignment to avoid latch
        data_we    = 1'b0;
        data_idx   = cur_index;
        data_way   = 2'd0;
        data_wsel  = cur_word;
        data_wdata = '0;

        unique case (state)
            S_IDLE: begin
                if (req_valid) begin
                    data_idx  = req_addr[9:4];
                    data_wsel = req_addr[3:2];
                end
            end
            S_LOOKUP: begin
                if (hit_found && cur_we) begin
                    data_idx   = cur_index;
                    data_way   = hit_way;
                    data_wsel  = cur_word;
                    data_wdata = (data_rd[hit_way] & ~strb_mask(cur_wstrb)) |
                                 (cur_wdata        &  strb_mask(cur_wstrb));
                    data_we    = 1'b1;
                end
            end
            S_MISS_SELECT: begin
                data_wsel = 2'd0; // Prep for writeback word 0
            end
            S_WRITEBACK_REQ: begin
                data_idx  = cur_index;
                data_way  = victim_way;
                data_wsel = xfer_cnt + 2'd1; // Prep for next writeback word
            end
            S_WRITEBACK_WAIT: begin
                data_idx  = cur_index;
                data_way  = victim_way;
                data_wsel = xfer_cnt + 2'd1; // Prep for next writeback word
            end
            S_REFILL_WAIT: begin
                if (mem_resp_valid) begin
                    data_idx   = cur_index;
                    data_way   = victim_way;
                    data_wsel  = xfer_cnt;
                    data_wdata = mem_resp_rdata;
                    data_we    = 1'b1;
                end
            end
            S_REFILL_COMPLETE: begin
                if (cur_we) begin
                    unique case (cur_word)
                        2'd0: refilled = refill_buf[31:0];
                        2'd1: refilled = refill_buf[63:32];
                        2'd2: refilled = refill_buf[95:64];
                        2'd3: refilled = refill_buf[127:96];
                    endcase
                    data_idx   = cur_index;
                    data_way   = victim_way;
                    data_wsel  = cur_word;
                    data_wdata = (refilled   & ~strb_mask(cur_wstrb)) |
                                 (cur_wdata  &  strb_mask(cur_wstrb));
                    data_we    = 1'b1;
                end
            end
            default: ;
        endcase
    end

    // sequential FSM logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            cur_addr      <= '0;
            cur_we        <= 1'b0;
            cur_wdata     <= '0;
            cur_wstrb     <= '0;
            resp_valid    <= 1'b0;
            resp_rdata    <= '0;
            mem_req_valid <= 1'b0;
            mem_req_we    <= 1'b0;
            mem_req_addr  <= '0;
            mem_req_wdata <= '0;
            victim_way    <= 2'd0;
            victim_addr   <= '0;
            xfer_cnt      <= 2'd0;
            refill_buf    <= '0;
            valid_bits    <= '0;
            dirty_bits    <= '0;
        end else begin
            // Pulse signals — deassert every cycle
            resp_valid    <= 1'b0;
            mem_req_valid <= 1'b0;

            unique case (state)
                S_IDLE: begin
                    if (req_valid) begin
                        cur_addr  <= req_addr;
                        cur_we    <= req_we;
                        cur_wdata <= req_wdata;
                        cur_wstrb <= req_wstrb;
                        state     <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    if (hit_found) begin
                        if (cur_we) begin
                            // WRITE HIT
                            dirty_bits[flat(cur_index, hit_way)] <= 1'b1;
                            resp_rdata <= '0;
                        end else begin
                            // READ HIT
                            resp_rdata <= data_rd[hit_way];
                        end
                        resp_valid <= 1'b1;
                        state      <= S_IDLE;
                    end else begin
                        state <= S_MISS_SELECT;
                    end
                end

                S_MISS_SELECT: begin
                    victim_way  <= sel_victim;
                    victim_addr <= {tag_rd[sel_victim], cur_index, 4'b0000};
                    xfer_cnt    <= 2'd0;

                    if (valid_bits[flat(cur_index, sel_victim)] &
                        dirty_bits[flat(cur_index, sel_victim)])
                        state <= S_WRITEBACK_REQ;
                    else
                        state <= S_REFILL_REQ;
                end

                S_WRITEBACK_REQ: begin
                    mem_req_valid <= 1'b1;
                    mem_req_we    <= 1'b1;
                    mem_req_addr  <= victim_addr + {28'd0, xfer_cnt, 2'b00};
                    mem_req_wdata <= data_rd[victim_way];
                    state         <= S_WRITEBACK_WAIT;
                end

                S_WRITEBACK_WAIT: begin
                    if (mem_resp_valid) begin
                        if (xfer_cnt == 2'd3) begin
                            xfer_cnt <= 2'd0;
                            state    <= S_REFILL_REQ;
                        end else begin
                            xfer_cnt <= xfer_cnt + 2'd1;
                            state    <= S_WRITEBACK_REQ;
                        end
                    end
                end

                S_REFILL_REQ: begin
                    mem_req_valid <= 1'b1;
                    mem_req_we    <= 1'b0;
                    mem_req_addr  <= {cur_addr[31:4], xfer_cnt, 2'b00};
                    state         <= S_REFILL_WAIT;
                end

                S_REFILL_WAIT: begin
                    if (mem_resp_valid) begin
                        unique case (xfer_cnt)
                            2'd0: refill_buf[31:0]   <= mem_resp_rdata;
                            2'd1: refill_buf[63:32]  <= mem_resp_rdata;
                            2'd2: refill_buf[95:64]  <= mem_resp_rdata;
                            2'd3: refill_buf[127:96] <= mem_resp_rdata;
                        endcase
                        if (xfer_cnt == 2'd3) begin
                            valid_bits[flat(cur_index, victim_way)] <= 1'b1;
                            dirty_bits[flat(cur_index, victim_way)] <= cur_we;
                            state <= S_REFILL_COMPLETE;
                        end else begin
                            xfer_cnt <= xfer_cnt + 2'd1;
                            state    <= S_REFILL_REQ;
                        end
                    end
                end

                S_REFILL_COMPLETE: begin
                    unique case (cur_word)
                        2'd0: resp_rdata <= cur_we ? '0 : refill_buf[31:0];
                        2'd1: resp_rdata <= cur_we ? '0 : refill_buf[63:32];
                        2'd2: resp_rdata <= cur_we ? '0 : refill_buf[95:64];
                        2'd3: resp_rdata <= cur_we ? '0 : refill_buf[127:96];
                    endcase
                    resp_valid <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
