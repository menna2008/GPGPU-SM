module l1_icache(
    input logic clk,
    input logic reset,

    // client interface (coalescing unit for data, fetch stage for instructions)
    input logic req_valid,
    output logic req_ready,
    input logic [31:0] req_addr,
    input logic [ID_W-1:0] req_id,
    input logic req_write,
    input logic [1023:0] wr_data, // store data
    input logic [31:0] wr_word_en, // which of the 32 words this store overwrites

    output logic rsp_valid, // fires for reads AND writes (write = completion ack)
    output logic [127:0] intrs,
    output logic [ID_W-1:0] rsp_id,

    // flush when the kernel is done
    input logic flush_start,
    output logic flush_done,

    // mem_arbiter interface
    // send out request
    output logic mem_req_valid,
    input logic mem_req_ready,
    output logic mem_req_write,
    output logic [31:0] mem_req_addr,  // always line-aligned

    // write request
    output logic mem_wvalid,
    input logic mem_wready,
    output logic mem_wlast,
    output logic [MEM_W-1:0] mem_wdata, // writeback burst, BEATS beats

    input logic [MEM_W-1:0] mem_rdata, // fill burst, BEATS beats
    input logic mem_rvalid,
    input logic mem_rlast
);
    logic [1023:0] rsp_line;

    l1_cache cache (.*);

     logic [4:0] word_idx_q;
    always_ff @(posedge clk)
        if (req_valid && req_ready)
            word_idx_q <= req_addr[6:2];

    assign instr = {
        rsp_line[32*(word_idx_q + 3) +: 32],
        rsp_line[32*(word_idx_q + 2) +: 32],
        rsp_line[32*(word_idx_q + 1) +: 32],
        rsp_line[32*word_idx_q +: 32],
    };
    // used concatentaion to allow wrap around 
    // and avoid X/Z values if the idx goes out of range
endmodule