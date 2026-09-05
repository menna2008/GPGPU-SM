`timescale 1ns/1ps
module tb_mask_split_unit;
    logic clk;
    logic reset;
    logic [1:0] sub_warp_cycle;
    logic accum_done;
    logic is_branch;
    logic [7:0] branch_taken_bits;
    logic [31:0] current_active_mask;
    logic [31:0] branch_pc;
    logic [5:0] push2_pc_recon_offset;
    logic [31:0] pc_taken;

    logic push2_valid;
    logic [31:0] push2_mask_taken;
    logic [31:0] push2_mask_not_taken;
    logic [31:0] push2_pc_taken;
    logic [31:0] push2_pc_fallthrough;
    logic [31:0] push2_recon_pc;

    int errors = 0;

    mask_split_unit DUT (
        .clk(clk),
        .reset(reset),
        .sub_warp_cycle(sub_warp_cycle),
        .accum_done(accum_done),
        .is_branch(is_branch),
        .branch_taken_bits(branch_taken_bits),
        .current_active_mask(current_active_mask),
        .branch_pc(branch_pc),
        .push2_pc_recon_offset(push2_pc_recon_offset),
        .pc_taken(pc_taken),
        .push2_valid(push2_valid),
        .push2_mask_taken(push2_mask_taken),
        .push2_mask_not_taken(push2_mask_not_taken),
        .push2_pc_taken(push2_pc_taken),
        .push2_pc_fallthrough(push2_pc_fallthrough),
        .push2_recon_pc(push2_recon_pc)
    );

    always #5 clk = ~clk;

    task automatic check(input logic [31:0] actual, expected);
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

    initial begin
        clk = 0;
        reset = 1;
        sub_warp_cycle = 2'd0;
        accum_done = 1'b0;
        is_branch = 1'b0;
        branch_taken_bits = 8'b0;
        current_active_mask = 32'b0;
        branch_pc = 32'b0;
        push2_pc_recon_offset = 6'b0;
        pc_taken = 32'b0;

        repeat (2) @(negedge clk);
        reset = 0;

        is_branch = 1'b1;
        branch_pc = 32'h0000_1000;
        pc_taken = 32'h0000_2000;
        push2_pc_recon_offset = 6'd4;
        current_active_mask = 32'hFFFF_FFFF;

        sub_warp_cycle = 2'd0; branch_taken_bits = 8'h01; accum_done = 1'b0; // byte0 = 0x01

        @(negedge clk);
        sub_warp_cycle = 2'd1; branch_taken_bits = 8'h02; accum_done = 1'b0; // byte1 = 0x02

        @(negedge clk);
        sub_warp_cycle = 2'd2; branch_taken_bits = 8'h03; accum_done = 1'b0; // byte2 = 0x03

        @(negedge clk);
        // Now sub_warp_cycle==3 is active (registered from the posedge we just crossed).
        // Assert accum_done COMBINATIONALLY in this same cycle, alongside byte3's
        // live value on branch_taken_bits, and sample push2_mask_taken WITHOUT
        // waiting for another clock edge -- this is the crux of the test.
        sub_warp_cycle = 2'd3; branch_taken_bits = 8'h04; accum_done = 1'b1; // byte3 = 0x04
        @(posedge clk);
        #1; // let combinational logic settle after signal changes

        $display("--- Sampling combinationally within sub_warp_cycle==3, accum_done==1 ---");
        $display("taken_bits expected = 32'h0403_0201 if byte3 landed in time, else 32'h00_030201 (byte3 missing)");
        check_bit(push2_valid, 1'b1);
        check(push2_mask_taken, 32'h0403_0201);
        check(push2_pc_taken, 32'h0000_2000);
        check(push2_pc_fallthrough, 32'h0000_1004);
        check(push2_recon_pc, 32'h0000_1004);

        @(negedge clk);
        accum_done = 1'b0;
        is_branch = 1'b0;
        @(negedge clk);
        check_bit(push2_valid, 1'b0);

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule