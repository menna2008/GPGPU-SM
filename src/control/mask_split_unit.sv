module mask_split_unit (
    input logic clk,
    input logic reset,
    input logic [1:0] sub_warp_cycle,
    input logic accum_done,

    // Information about the branch
    input logic is_branch,
    input logic [7:0] branch_taken_bits, // 1 bit per lane (8 total)
    input logic [31:0] current_active_mask, // only currently active lanes can stay active
    // Info for calculating reconvergence PC
    input logic [31:0] branch_pc,
    input logic [5:0] push2_pc_recon_offset,
    input logic [31:0] pc_taken,

    output logic push2_valid,
    output logic [31:0] push2_mask_taken,
    output logic [31:0] push2_mask_not_taken,
    output logic [31:0] push2_pc_taken,
    output logic [31:0] push2_pc_fallthrough, // branch_pc + 4
    output logic [31:0] push2_recon_pc // branch_pc + push2_pc_recon_offset
);
    logic [31:0] taken_bits_accum;

    always_ff @(posedge clk) begin
        if (reset) begin
            taken_bits_accum <= 32'b0;
        end else if (is_branch) begin
            case (sub_warp_cycle)
                2'd0: taken_bits_accum[7:0] <= branch_taken_bits;
                2'd1: taken_bits_accum[15:8] <= branch_taken_bits;
                2'd2: taken_bits_accum[23:16] <= branch_taken_bits;
                2'd3: taken_bits_accum[31:24] <= branch_taken_bits;
            endcase
        end
    end

    always_comb begin
        if (reset) begin
            push2_valid = 1'b0;
            push2_mask_taken = 32'b0;
            push2_mask_not_taken = 32'b0;
            push2_pc_taken = 32'b0;
            push2_pc_fallthrough = 32'b0;
            push2_recon_pc = 32'b0;
        end else if (accum_done) begin
            push2_mask_taken = current_active_mask & taken_bits_accum;
            push2_mask_not_taken = current_active_mask & ~taken_bits_accum;
            push2_pc_taken = pc_taken;
            push2_pc_fallthrough = branch_pc + 32'd4;
            push2_recon_pc = branch_pc + {{26{push2_pc_recon_offset[5]}}, push2_pc_recon_offset};
        end

        push2_valid = accum_done;
    end
endmodule