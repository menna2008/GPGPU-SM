module recon_stack_tb;
    logic clk, reset;
    logic init_push, push2_valid;
    logic [31:0] init_mask, init_pc, init_recon_pc;
    logic [31:0] push2_branch_pc, push2_mask_taken, push2_mask_not_taken;
    logic [31:0] push2_pc_taken, push2_pc_fallthrough;
    logic [5:0] push2_pc_recon_offset;
    
    logic current_pc_valid;
    logic [31:0] current_pc;

    logic [31:0] top_mask, top_pc, top_recon_pc;
    logic stack_empty, stack_full, push2_done;

    int errors = 0;

    // Instantiate DUT
    recon_stack DUT (
        .clk(clk),
        .reset(reset),
        .init_push(init_push),
        .init_mask(init_mask),
        .init_pc(init_pc),
        .init_recon_pc(init_recon_pc),
        .push2_valid(push2_valid),
        .push2_branch_pc(push2_branch_pc),
        .push2_mask_taken(push2_mask_taken),
        .push2_mask_not_taken(push2_mask_not_taken),
        .push2_pc_taken(push2_pc_taken),
        .push2_pc_fallthrough(push2_pc_fallthrough),
        .push2_pc_recon_offset(push2_pc_recon_offset),
        .push2_done(push2_done),
        .current_pc_valid(current_pc_valid),
        .current_pc(current_pc),
        .top_mask(top_mask),
        .top_pc(top_pc),
        .top_recon_pc(top_recon_pc),
        .stack_empty(stack_empty),
        .stack_full(stack_full)
    );

    always #5 clk = ~clk;
    
    task do_reset;
        begin
            reset = 1'b1;
            init_push = 1'b0; push2_valid = 1'b0; current_pc_valid = 1'b0;
            init_mask = '0; init_pc = '0; init_recon_pc = '0;
            push2_branch_pc = '0; push2_mask_taken = '0; push2_mask_not_taken = '0;
            push2_pc_taken = '0; push2_pc_fallthrough = '0; push2_pc_recon_offset = '0;
            current_pc = '0;
            @(negedge clk);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task check_pc(input [31:0] pc);
        begin
            @(negedge clk);
            current_pc = pc; current_pc_valid = 1'b1;
            @(negedge clk);
            current_pc_valid = 1'b0;
        end
    endtask

    task check_top(input [31:0] exp_mask, exp_pc, exp_recon_pc);
        begin
            if (top_mask !== exp_mask || top_pc !== exp_pc || top_recon_pc !== exp_recon_pc) begin
                $error("FAIL | got mask = %h pc = %h recon = %h | expected mask = %h pc = %h recon = %h",
                        top_mask, top_pc, top_recon_pc, exp_mask, exp_pc, exp_recon_pc);
                errors++;
            end else begin
                $display("PASS | mask = %h pc = %h recon = %h", top_mask, top_pc, top_recon_pc);
            end
        end
    endtask

    task check_flags(input logic exp_empty, exp_full);
        begin
            if (stack_empty !== exp_empty || stack_full !== exp_full) begin
                $error("FAIL | got empty = %b full = %b, expected empty = %b full = %b",
                        stack_empty, stack_full, exp_empty, exp_full);
                errors++;
            end else begin
                $display("PASS | empty = %b full = %b", stack_empty, stack_full);
            end
        end
    endtask

    task check_push2_done(input logic exp_done);
        begin
            if (push2_done !== exp_done) begin
                $error("FAIL | got push2_done = %b, expected push2_done = %b", push2_done, exp_done);
                errors++;
            end else begin
                $display("PASS | push2_done = %b", push2_done);
            end
        end
    endtask

    task kernel_launch(input [31:0] mask, pc, recon_pc);
        @(negedge clk);
        init_push = 1'b1; init_mask = mask; init_pc = pc; init_recon_pc = recon_pc;
        @(negedge clk);
        init_push = 1'b0;
    endtask

    task push(input [31:0] branch_pc, mask_taken, mask_not_taken, pc_taken, pc_fallthrough,
             input [5:0] recon_offset,
             input exp_push2_done);
        @(negedge clk);
        push2_valid = 1'b1; push2_branch_pc = branch_pc;
        push2_mask_taken = mask_taken; push2_mask_not_taken = mask_not_taken;
        push2_pc_taken = pc_taken; push2_pc_fallthrough = pc_fallthrough;
        push2_pc_recon_offset = recon_offset;

        #1; check_push2_done(exp_push2_done);

        @(negedge clk);
        push2_valid = 1'b0;
    endtask

    initial begin
        clk = 0;
        do_reset();
        
        // 1. Kernel launch
        $display("Kernel Launch");
        kernel_launch(32'hFFFF_FFFF, 32'h0000_1000, 32'hFFFFFFFF);
        check_top(32'hFFFF_FFFF, 32'h0000_1000, 32'hFFFF_FFFF);
        check_flags(1'b0, 1'b0);

        // 2. Divergent branch at PC=0x1000, recon_offset = +12
        // reconverge at 0x1000 + 12 = 0x100C
        $display("Push divergent branch resolution");
        push(32'h0000_1000, 32'h0F0F_0F0F, 32'hF0F0_F0F0, 32'h0000_1008, 32'h0000_1004, 6'd12, 1'b1);
        check_top(32'h0F0F_0F0F, 32'h0000_1008, 32'h0000_100C);  // taken entry, not fallthrough
        check_flags(1'b0, 1'b0);

        // 3. Feed a current_pc that does NOT match reconverge_pc — should not pop
        $display("Set PC to non-reconvergent PC, do not pop");
        check_pc(32'h0000_1004);
        check_top(32'h0F0F_0F0F, 32'h0000_1004, 32'h0000_100C);

        // 4. Feed current_pc == reconverge_pc
        // should pop, revealing not-taken branch
        $display("current_pc == reconvergence_pc => top should be not-taken branch");
        check_pc(32'h0000_100C);
        check_top(32'hF0F0_F0F0, 32'h0000_1004, 32'h0000_100C);

        // 5. Pop again
        // top is now the base entry
        $display("Second pop => top should be parent");
        check_pc(32'h0000_100C);
        check_top(32'hFFFF_FFFF, 32'h0000_100C, 32'hFFFF_FFFF);
        check_flags(1'b0, 1'b0);

        // 6. Bodyless-else case: skip_taken == 1 therefore push_count == 1
        //    branch_pc=0x2000, recon_offset=8 -> curr_recon_pc=0x2008
        //    pc_fallthrough=0x2008 (== recon -> skipped), pc_taken=0x2004 (real body)
        $display("Push divergent branch (skip taken => push_count=1)");
        push(32'h0000_2000, 32'hAAAA_AAAA, 32'h5555_5555, 32'h0000_2008, 32'h0000_2004, 6'd8, 1'b1);
        check_top(32'h5555_5555, 32'h0000_2004, 32'h0000_2008);   // only fallthrough entry pushed
        check_flags(1'b0, 1'b0);

        $display("Pop the branch => top should be parent with updated pc");
        check_pc(32'h0000_2008);
        check_top(32'hFFFF_FFFF, 32'h0000_2008, 32'hFFFF_FFFF);
        check_flags(1'b0, 1'b0);

        // 7. Overflow test: push2 repeatedly until stack_full, then attempt one more
        for (int i = 0; i < 3; i++) begin
            push(32'h0000_2004 + i*4, 32'h0000_0001, 32'h0000_0002, 32'h0000_200C + i*4, 32'h0000_2008 + i*4, 6'd12, 1'b1);
        end
        $display("stack_full == 1 after repeated push2");
        check_flags(1'b0, 1'b1);

        // Attempt push2 while full (top should not change from previous cycle)
        $display("Still full after overflow attempt (write should be rejected)");
        push(32'h1234_5678, 32'hAAAA_AAAA, 32'h5555_5555, 32'hDEAD_0004, 32'hDEAD_0008, 6'd4, 1'b0);
        
        check_flags(1'b0, 1'b1);
        check_top(32'h0000_0001, 32'h0000_2014, 32'h0000_2018);
        $display("errors = %0d", errors);
        $finish;
    end
endmodule