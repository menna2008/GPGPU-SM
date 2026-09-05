`default_nettype none
module int_alu (
    input logic clk,
    input logic valid_in,
    input logic [5:0] opcode,
    input logic [31:0] src1,
    input logic [31:0] src2,
    
    // PC and offset for branch instructions
    input logic [31:0] PC,
    input logic [15:0] offset,
    output logic valid_out,
    output logic branch_taken,
    output logic [31:0] result,

    // Input warp_id, thread_slot, and dest_register for writeback_arbiter
    input logic [9:0] reg_bank_addr_in,

    // Output warp_id, thread_slot, and dest_register for writeback_arbiter
    // This is simply the input passed to the output
    output logic [9:0] reg_bank_addr_out
);
    // Define parameters for instruction types
    localparam R_TYPE = 3'b000, I_TYPE = 3'b001, FMA = 3'b010, BRANCH = 3'b011, SPECIAL = 3'b100, DONE = 3'b111;

    // Define parameters for specific instructions
    // R-type instructions
    localparam [2:0] NOP = 3'b000, ADD  = 3'b001, SUB  = 3'b010;
    localparam [2:0] AND  = 3'b011, OR  = 3'b100, SLT = 3'b101;
    localparam [2:0] MUL = 3'b110;

    // I-type instructions
    localparam [2:0] LUI = 3'b000, ADDI = 3'b001, SUBI = 3'b010;
    localparam [2:0] ANDI = 3'b011, ORI = 3'b100, SLTI = 3'b101;
    localparam [2:0] LOAD = 3'b110, STORE = 3'b111;

    // Branch instructions
    localparam [2:0] BEQ = 3'b000, BNE = 3'b001;
    localparam [2:0] BLT = 3'b010, BGE = 3'b011;

    always_comb begin
        if (reset) begin
            valid_out = 1'b0;
            branch_taken = 1'b0;
            result = 32'b0;
        end else begin
            valid_out = valid_in;
            branch_taken = 1'b0;

            case (opcode[5:3]) // case by opcode
                R_TYPE : case (opcode[2:0]) // case by sub opcode
                    NOP : result = 32'b0;
                    ADD : result = src1 + src2;
                    SUB : result = src1 - src2;
                    MUL : result = src1 * src2;
                    AND : result = src1 & src2;
                    OR  : result = src1 | src2;
                    SLT : result = $signed(src1) < $signed(src2);
                    default: result = 32'b0;
                endcase

                I_TYPE : case (opcode[2:0])
                    LUI  : result = {src1[15:0], 16'b0};
                    LOAD, STORE,
                    ADDI : result = src1 + src2;
                    SUBI : result = src1 - src2;
                    ANDI : result = src1 & src2;
                    ORI  : result = src1 | src2;
                    SLTI : result = $signed(src1) < $signed(src2);
                    default : result = 32'b0;
                endcase

                BRANCH : begin
                    result = PC + {{22{offset[15]}}, offset[15:6]};
                    case (opcode[2:0])
                        BEQ : branch_taken = (src1 == src2);
                        BNE : branch_taken = (src1 != src2);
                        BLT : branch_taken = ($signed(src1) < $signed(src2));
                        BGE : branch_taken = ($signed(src1) >= $signed(src2));
                    endcase
                end
                
                default : result = 32'b0;
            endcase
        end
    end

    assign reg_bank_addr_out = reg_bank_addr_in;
endmodule