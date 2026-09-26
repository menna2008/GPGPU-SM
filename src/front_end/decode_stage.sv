module decode_stage (
    input logic clk,
    input logic reset,

    input logic sub_warp_valid,
    input logic [1:0] sub_warp_cycle,
    input logic [2:0] curr_warp,
    input logic [31:0] active_mask,

    input logic [31:0] instr,
    input logic [31:0] instr_pc,

    output logic sub_warp_valid_q,
    output logic [1:0] sub_warp_cycle_q,
    
    output logic [5:0] opcode_q,

    output logic [7:0] alu_valid_q,
    output logic [7:0] fma_valid_q,
    output logic [7:0] special_reg_valid_q,

    output logic [9:0] dest_addr_q,
    output logic [15:0] imm_q,
    output logic [31:0] instr_pc_q
);
    localparam R_TYPE = 3'b000, I_TYPE = 3'b001, FMA = 3'b010, BRANCH = 3'b011, SPECIAL = 3'b100;
    
    logic [2:0] format;
    logic [5:0] opcode;
    logic [4:0] dst;
    logic [9:0] dest_addr;
    logic [15:0] imm;
    logic alu_valid, fma_valid, special_reg_valid;
    logic [7:0] curr_active_mask;

    always_comb begin
        format = instr[31:29];
        opcode = instr[31:26];
        alu_valid = 1'b0;
        fma_valid = 1'b0;
        special_reg_valid = 1'b0;

        case (format)
            R_TYPE : begin
                dst = instr[15:11];
                alu_valid = 1'b1;
            end
            I_TYPE : begin
                dst = instr[20:16];
                alu_valid = 1'b1;
            end
            FMA : begin
                dst = instr[10:6];
                fma_valid = 1'b1;
            end
            SPECIAL : begin
                dst = instr[25:21];
                special_reg_valid = 1'b1;
            end
            BRANCH : begin
                dst = 5'b0;
                alu_valid = 1'b1;
            end
            default : dst = 5'b0;
        endcase

        dest_addr = {curr_warp, sub_warp_cycle, dst};
        imm = instr[15:0];
        curr_active_mask = active_mask[sub_warp_cycle*8 +: 8];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            sub_warp_valid_q <= 1'b0;
            sub_warp_cycle_q <= 2'b0;
            opcode_q <= 6'b0;
            alu_valid_q <= 1'b0;
            fma_valid_q <= 1'b0;
            special_reg_valid_q <= 1'b0;
            dest_addr_q <= 10'b0;
            imm_q <= 16'b0;
            instr_pc_q <= 32'b0;
        end else begin
            sub_warp_valid_q <= sub_warp_valid;
            sub_warp_cycle_q <= sub_warp_cycle;
            opcode_q <= opcode;
            alu_valid_q <= curr_active_mask & {8{alu_valid}};
            fma_valid_q <= curr_active_mask & {8{fma_valid}};
            special_reg_valid_q <= curr_active_mask & {8{special_reg_valid}};
            dest_addr_q <= dest_addr;
            imm_q <= imm;
            instr_pc_q <= instr_pc;
        end
    end
endmodule