`timescale 1ns/1ps
module tb_int_alu;
    logic clk;
    logic reset;
    logic valid_in;
    logic [5:0] opcode;
    logic [31:0] src1, src2;
    logic [31:0] PC;
    logic [15:0] offset;
    logic valid_out;
    logic branch_taken;
    logic [31:0] result;
    logic [9:0] reg_bank_addr_in;
    logic [9:0] reg_bank_addr_out;

    int errors = 0;

    int_alu DUT (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        .opcode(opcode),
        .src1(src1),
        .src2(src2),
        .PC(PC),
        .offset(offset),
        .valid_out(valid_out),
        .branch_taken(branch_taken),
        .result(result),
        .reg_bank_addr_in(reg_bank_addr_in),
        .reg_bank_addr_out(reg_bank_addr_out)
    );

    always #5 clk = ~clk;

    // Opcode encodings: {format[2:0], suboptype[2:0]}
    localparam [5:0] NOP = 6'b000000, ADD = 6'b000001, SUB = 6'b000010;
    localparam [5:0] AND = 6'b000011, OR  = 6'b000100, SLT = 6'b000101;
    localparam [5:0] MUL = 6'b000110;

    // I-type instructions
    localparam [5:0] LUI = 6'b001000, ADDI = 6'b001001, SUBI = 6'b001010;
    localparam [5:0] ANDI = 6'b001011, ORI = 6'b001100, SLTI = 6'b001101;
    localparam [5:0] LOAD = 6'b001110, STORE = 6'b001111;

    // Branch instructions
    localparam [5:0] BEQ = 6'b011000, BNE = 6'b011001;
    localparam [5:0] BLT = 6'b011010, BGE = 6'b011011;

    task automatic check_result(input logic [31:0] actual, input logic [31:0] expected);
        if (actual !== expected) begin
            $error("FAIL | expected = %0h actual = %0h", expected, actual);
            errors++;
        end else begin
            $display("PASS | %0h", actual);
        end
    endtask

    task automatic check_bit(input logic actual, input logic expected);
        if (actual !== expected) begin
            $error("FAIL | expected = %0b actual = %0b", expected, actual);
            errors++;
        end else begin
            $display("PASS | %0b", actual);
        end
    endtask

    // Drives inputs combinationally and settles before checking -- DUT has no
    // registered logic (clk is unused inside int_alu), so no clock wait is
    // structurally required, but we still tick #1 after driving to be safe
    // against simulator event-ordering, and to mirror realistic testbench style.
    task automatic drive(
        input logic [5:0] task_opcode,
        input logic [31:0] task_src1,
        input logic [31:0] task_src2,
        input logic [31:0] task_pc,
        input logic [15:0] task_offset
    );
        valid_in = 1'b1;
        opcode = task_opcode;
        src1 = task_src1;
        src2 = task_src2;
        PC = task_pc;
        offset = task_offset;
        #1;
    endtask

    initial begin
        clk = 0;
        reset = 1;
        valid_in = 0;
        opcode = 6'b0;
        src1 = 32'b0;
        src2 = 32'b0;
        PC = 32'b0;
        offset = 16'b0;
        reg_bank_addr_in = 10'b0;

        #1;
        $display("reset: valid_out = 0, branch_taken = 0, result = 32'b0");
        check_bit(valid_out, 1'b0);
        check_bit(branch_taken, 1'b0);
        check_result(result, 32'b0);

        reset = 0;

        // R-type
        $display("\nNOP");
        drive(NOP, 32'd5, 32'd7, 32'b0, 16'b0);
        check_result(result, 32'b0);

        $display("ADD");
        drive(ADD, 32'd10, 32'd15, 32'b0, 16'b0);
        check_result(result, 32'd25);

        $display("SUB");
        drive(SUB, 32'd20, 32'd8, 32'b0, 16'b0);
        check_result(result, 32'd12);

        $display("AND");
        drive(AND, 32'hFF00FF00, 32'h0FF00FF0, 32'b0, 16'b0);
        check_result(result, 32'h0F000F00);

        $display("OR");
        drive(OR, 32'hF0F0F0F0, 32'h0F0F0F0F, 32'b0, 16'b0);
        check_result(result, 32'hFFFFFFFF);

        $display("SLT (1 => true, 2 => false, 3 => signed negative < positive)");
        drive(SLT, 32'd3, 32'd5, 32'b0, 16'b0);
        check_result(result, 32'd1);
        drive(SLT, 32'd5, 32'd3, 32'b0, 16'b0);
        check_result(result, 32'd0);
        drive(SLT, -32'sd5, 32'd1, 32'b0, 16'b0); // signed comparison
        check_result(result, 32'd1);

        $display("MUL");
        drive(MUL, 32'd6, 32'd7, 32'b0, 16'b0);
        check_result(result, 32'd42);

        // I-type
        $display("\nLUI");
        drive(LUI, 32'h0000_ABCD, 32'b0, 32'b0, 16'b0);
        check_result(result, 32'hABCD_0000);

        $display("ADDI");
        drive(ADDI, 32'd100, 32'd23, 32'b0, 16'b0);
        check_result(result, 32'd123);

        $display("SUBI");
        drive(SUBI, 32'd100, 32'd23, 32'b0, 16'b0);
        check_result(result, 32'd77);

        $display("ANDI");
        drive(ANDI, 32'hFFFF_FFFF, 32'h0000_00FF, 32'b0, 16'b0);
        check_result(result, 32'h0000_00FF);

        $display("ORI");
        drive(ORI, 32'h0000_0000, 32'h0000_00FF, 32'b0, 16'b0);
        check_result(result, 32'h0000_00FF);

        $display("SLTI");
        drive(SLTI, 32'd3, 32'd5, 32'b0, 16'b0);
        check_result(result, 32'd1);

        $display("LOAD"); // address = base + offset
        drive(LOAD, 32'h0000_1000, 32'd16, 32'b0, 16'b0);
        check_result(result, 32'h0000_1010);

        $display("STORE"); // address = base + offset
        drive(STORE, 32'h0000_2000, 32'd32, 32'b0, 16'b0);
        check_result(result, 32'h0000_2020);

        // Branch: target-offset calculation
        // offset[15:6] = target_offset (10b signed), offset[5:0] = reconv_offset
        $display("BRANCH target (positive target_offset=4, reconv_offset ignored)");
        drive(BEQ, 32'd5, 32'd5, 32'h0000_1000, {10'sd4, 6'b111111});
        check_result(result, 32'h0000_1004);
        check_bit(branch_taken, 1'b1);

        // Negative target_offset, sign-extension check
        // -4 in 10-bit two's complement = 10'b1111111100
        $display("BRANCH target (negative target_offset=-4, sign-extended)");
        drive(BEQ, 32'd5, 32'd5, 32'h0000_1000, {10'b1111111100, 6'b000000});
        check_result(result, 32'h0000_0FFC);

        $display("BNE taken (not equal)");
        drive(BNE, 32'd5, 32'd6, 32'h0000_2000, {10'sd8, 6'b0});
        check_bit(branch_taken, 1'b1);
        $display("BNE not taken (equal)");
        drive(BNE, 32'd5, 32'd5, 32'h0000_2000, {10'sd8, 6'b0});
        check_bit(branch_taken, 1'b0);

        $display("BLT taken");
        drive(BLT, -32'sd3, 32'd1, 32'h0000_3000, {10'sd8, 6'b0});
        check_bit(branch_taken, 1'b1);
        $display("BLT not taken");
        drive(BLT, 32'd10, 32'd1, 32'h0000_3000, {10'sd8, 6'b0});
        check_bit(branch_taken, 1'b0);

        $display("BGE taken");
        drive(BGE, 32'd10, 32'd1, 32'h0000_4000, {10'sd8, 6'b0});
        check_bit(branch_taken, 1'b1);
        $display("BGE not taken");
        drive(BGE, 32'd1, 32'd10, 32'h0000_4000, {10'sd8, 6'b0});
        check_bit(branch_taken, 1'b0);

        // valid_out check
        valid_in = 1'b1;
        #1; $display("valid_out = valid_in (1)");
        check_bit(valid_out, 1'b1);
        valid_in = 1'b0;
        #1; $display("valid_out = valid_in (0)");
        check_bit(valid_out, 1'b0);

        // reg_bank_addr check
        reg_bank_addr_in = 10'b10_11_00110;
        #1;
        if (reg_bank_addr_out !== reg_bank_addr_in) begin
            $error("FAIL [reg_bank_addr passthrough]: expected=%0b actual=%0b", reg_bank_addr_in, reg_bank_addr_out);
            errors++;
        end else begin
            $display("PASS [reg_bank_addr passthrough]: %0b", reg_bank_addr_out);
        end

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule