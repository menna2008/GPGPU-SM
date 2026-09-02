module writeback_arbiter (
    input wire clk,
    input wire reset,

    // Results
    input wire [31:0] alu_data,
    input wire [31:0] fma_data,
    input wire [31:0] lsu_data,

    // Register file addresses
    input wire [9:0] alu_addr,
    input wire [9:0] fma_addr,
    input wire [9:0] lsu_addr,

    // Valid bits
    input wire alu_valid,
    input wire fma_valid,
    input wire lsu_valid,

    // Output address, data, and write enable to register bank
    output wire [9:0] rf_write_addr,
    output wire [31:0] rf_write_data,
    output wire rf_write_enable,

    // Backpressure — stall issue of instructions of this result type
    output wire alu_full,
    output wire fma_full,
    output wire lsu_full
);
    // signals to FIFOs
    wire lsu_empty, fma_empty, alu_empty;
    wire [9:0] lsu_head_addr, fma_head_addr, alu_head_addr;
    wire [31:0] lsu_head_data, fma_head_data, alu_head_data;

    wire grant_lsu_fifo, grant_fma_fifo, grant_alu_fifo;
    wire grant_lsu_curr, grant_fma_curr, grant_alu_curr;
    wire all_fifos_empty;

    // Decide which source to choose from
    // FIFOs get priority since they contain data from older instructions
    // The priority logic of the FIFOs is: LSU FIFO > FMA FIFO > ALU FIFO
    // If all FIFOs are empty then priority we choose from the incoming signals
    // using the same priority logic as the FIFOs

    assign grant_lsu_fifo = !lsu_empty;
    assign grant_fma_fifo = lsu_empty && !fma_empty;
    assign grant_alu_fifo = lsu_empty && fma_empty && !alu_empty;

    assign all_fifos_empty = lsu_empty && fma_empty && alu_empty;

    assign grant_lsu_curr = all_fifos_empty && lsu_valid;
    assign grant_fma_curr = all_fifos_empty && !lsu_valid && fma_valid;
    assign grant_alu_curr = all_fifos_empty && !lsu_valid && !fma_valid && alu_valid;

    // Write is enabled if any of the data sources are granted access to the rf write port

    assign rf_write_enable = grant_lsu_fifo || grant_fma_fifo || grant_alu_fifo ||
                             grant_lsu_curr || grant_fma_curr || grant_alu_curr;

    // Output the address and data from the correct source

    assign rf_write_addr = grant_lsu_fifo ? lsu_head_addr :
                           grant_fma_fifo ? fma_head_addr :
                           grant_alu_fifo ? alu_head_addr :
                           grant_lsu_curr ? lsu_addr :
                           grant_fma_curr ? fma_addr :
                           grant_alu_curr ? alu_addr :
                           10'bx;

    assign rf_write_data = grant_lsu_fifo ? lsu_head_data :
                           grant_fma_fifo ? fma_head_data :
                           grant_alu_fifo ? alu_head_data :
                           grant_lsu_curr ? lsu_data :
                           grant_fma_curr ? fma_data :
                           grant_alu_curr ? alu_data :
                           32'bx;

    // The data from each source is pushed to its respective FIFO if wasn't written this cycle
    // Pop from a FIFO if its data is written to the register

    wire lsu_push, fma_push, alu_push;
    wire lsu_pop, fma_pop, alu_pop;

    assign lsu_push = lsu_valid && !grant_lsu_curr;
    assign fma_push = fma_valid && !grant_fma_curr;
    assign alu_push = alu_valid && !grant_alu_curr;

    assign lsu_pop = grant_lsu_fifo;
    assign fma_pop = grant_fma_fifo;
    assign alu_pop = grant_alu_fifo;

    result_fifo #(.DEPTH(2)) lsu_fifo (
        .clk(clk),
        .reset(reset),

        .push(lsu_push),
        .push_addr(lsu_addr),
        .push_data(lsu_data),
        .pop(lsu_pop),
        
        .head_addr(lsu_head_addr),
        .head_data(lsu_head_data),
        
        .empty(lsu_empty),
        .full(lsu_full)
    );

    result_fifo #(.DEPTH(3)) fma_fifo (
        .clk(clk),
        .reset(reset),

        .push(fma_push),
        .push_addr(fma_addr),
        .push_data(fma_data),

        .pop(fma_pop),
        .head_addr(fma_head_addr),
        .head_data(fma_head_data),
        
        .empty(fma_empty),
        .full(fma_full)
    );

    result_fifo #(.DEPTH(4)) alu_fifo (
        .clk(clk),
        .reset(reset),
        
        .push(alu_push),
        .push_addr(alu_addr),
        .push_data(alu_data),

        .pop(alu_pop),
        .head_addr(alu_head_addr),
        .head_data(alu_head_data),
        
        .empty(alu_empty),
        .full(alu_full)
    );
endmodule