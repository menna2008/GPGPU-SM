module writeback_arbiter (
    input logic clk,
    input logic reset,

    // Results
    input logic [31:0] alu_data,
    input logic [31:0] fma_data,
    input logic [31:0] lsu_data,

    // Register file addresses
    input logic [9:0] alu_addr,
    input logic [9:0] fma_addr,
    input logic [9:0] lsu_addr,

    // Valid bits
    input logic alu_valid,
    input logic fma_valid,
    input logic lsu_valid,

    // Output address, data, and write enable to register bank
    output logic [9:0] rf_write_addr,
    output logic [31:0] rf_write_data,
    output logic rf_write_enable,

    // Backpressure — stall issue of instructions of this result type
    output logic buffer_full
);
    // signals to FIFOs
    logic buffer_empty;
    logic [9:0] buffer_head_addr;
    logic [31:0] buffer_head_data;

    logic grant_buffer;
    logic grant_lsu_curr, grant_fma_curr, grant_alu_curr;

    // Decide which source to choose from
    // FIFO gets priority since it contains data from older instructions
    // The priority logic for incomg signals is: LSU > FMA > ALU

    assign grant_buffer = !buffer_empty;

    assign grant_lsu_curr = buffer_empty && lsu_valid;
    assign grant_fma_curr = buffer_empty && !lsu_valid && fma_valid;
    assign grant_alu_curr = buffer_empty && !lsu_valid && !fma_valid && alu_valid;

    // Write is enabled if any of the data sources are granted access to the rf write port

    assign rf_write_enable = grant_buffer || grant_lsu_curr || grant_fma_curr || grant_alu_curr;

    // Output the address and data from the correct source

    assign rf_write_addr = grant_buffer   ? buffer_head_addr :
                           grant_lsu_curr ? lsu_addr :
                           grant_fma_curr ? fma_addr :
                           grant_alu_curr ? alu_addr :
                           10'bx;

    assign rf_write_data = grant_buffer   ? buffer_head_data :
                           grant_lsu_curr ? lsu_data :
                           grant_fma_curr ? fma_data :
                           grant_alu_curr ? alu_data :
                           32'bx;

    // The data from each source is pushed to the FIFO if it wasn't written this cycle
    // Pop from a FIFO if its data is written to the register

    logic lsu_push, fma_push, alu_push;
    logic buffer_pop;

    assign lsu_push = lsu_valid && !grant_lsu_curr;
    assign fma_push = fma_valid && !grant_fma_curr;
    assign alu_push = alu_valid && !grant_alu_curr;

    assign buffer_pop = grant_buffer;

    fifo #(.DEPTH(8)) buffer (
        .clk(clk),
        .reset(reset),
        
        .lsu_push(lsu_push),
        .lsu_addr(lsu_addr),
        .lsu_data(lsu_data),

        .fma_push(fma_push),
        .fma_addr(fma_addr),
        .fma_data(fma_data),

        .alu_push(alu_push),
        .alu_addr(alu_addr),
        .alu_data(alu_data),

        .pop(buffer_pop),
        .head_addr(buffer_head_addr),
        .head_data(buffer_head_data),
        
        .empty(buffer_empty),
        .full(buffer_full)
    );
endmodule