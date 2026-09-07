`timescale 1ns/1ps
module commit_tracker_tb;
    logic clk, reset;
    logic rf_write_enable;
    logic [2:0] rf_write_warp_id;
    logic commit_done;
    logic [2:0] commit_warp_id;

    int errors = 0;

    commit_tracker DUT (
        .clk(clk),
        .reset(reset),
        .rf_write_enable(rf_write_enable),
        .rf_write_warp_id(rf_write_warp_id),
        .commit_done(commit_done),
        .commit_warp_id(commit_warp_id)
    );

    always #5 clk = ~clk;

    task automatic do_write(input [2:0] wid);
        @(negedge clk);
        rf_write_enable = 1;
        rf_write_warp_id = wid;
        @(posedge clk);
        #1;
    endtask

    task automatic clear_write();
        @(negedge clk);
        rf_write_enable = 0;
        @(posedge clk);
    endtask

    initial begin
        clk = 0;
        reset = 1;
        rf_write_enable = 0;
        rf_write_warp_id = 3'd0;

        // Reset
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);
        #1;
        $display("post-reset: commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin
            errors++;
            $display("FAIL | expected commit_done=0");
        end

        $display("Write to warp 2 (cycle 0) commit_done = %0b", commit_done);
        do_write(3'd2);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd2);
        $display("Write to warp 2 (cycle 1) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd2);
        $display("Write to warp 2 (cycle 2) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd2);
        $display("Write to warp 2 (cycle 3) commit_done = %0b commit_warp_id = %0d", commit_done, commit_warp_id);
        if (commit_done !== 1'b1 || commit_warp_id !== 3'd2) begin
            errors++;
            $display("FAIL | expected commit_done = 1, warp_id = 2");
        end
        clear_write();

        // Write to warp5 with gaps between writes
        do_write(3'd5);
        $display("Write to warp 5 (cycle 0) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end
        clear_write();
        repeat (3) @(posedge clk); // gap

        do_write(3'd5);
        $display("Write to warp 5 (cycle 1) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end
        clear_write();
        repeat (2) @(posedge clk);

        do_write(3'd5);
        $display("Write to warp 5 (cycle 2) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end
        clear_write();

        do_write(3'd5);
        $display("Write to warp 5 (cycle 3) commit_done = %0b commit_warp_id = %0d", commit_done, commit_warp_id);
        if (commit_done !== 1'b1 || commit_warp_id !== 3'd5) begin
            errors++;
            $display("FAIL | expected commit_done = 1, warp_id = 5");
        end
        clear_write();

        // Writes to warp1 and warp3
        do_write(3'd1);
        $display("Write to warp 1 (cycle 0) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd3);
        $display("Write to warp 3 (cycle 0) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd1);
        $display("Write to warp 1 (cycle 1) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd3);
        $display("Write to warp 3 (cycle 1) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd1);
        $display("Write to warp 1 (cycle 2) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd3);
        $display("Write to warp 3 (cycle 2) commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd1);
        $display("Write to warp 1 (cycle 3) commit_done = %0b commit_warp_id = %0d", commit_done, commit_warp_id);
        if (commit_done !== 1'b1 || commit_warp_id !== 3'd1) begin
            errors++;
            $display("FAIL | expected commit_done = 1, warp_id = 1");
        end

        do_write(3'd3);
        $display("Write to warp 3 (cycle 3) commit_done = %0b commit_warp_id = %0d", commit_done, commit_warp_id);
        if (commit_done !== 1'b1 || commit_warp_id !== 3'd3) begin
            errors++;
            $display("FAIL | expected commit_done = 1, warp_id = 3");
        end
        clear_write();

        // commit_done is low the cycle after, doesn't stick ---
        @(posedge clk);
        #1;
        $display("commit_done is low one cycle later: commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        // Reset mid-count
        do_write(3'd4);
        do_write(3'd4);
        $display("Warp 4 (cycle 1) before reset: commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end
        clear_write();

        reset = 1;
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);
        #1;

        do_write(3'd4);
        $display("Warp 4 (cycle 0 after reset): commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd4);
        $display("Warp 4 (cycle 1 after reset): commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd4);
        $display("Warp 4 (cycle 2 after reset): commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd4);
        $display("Warp 4 (cycle 3 after reset) commit_done = %0b commit_warp_id = %0d", commit_done, commit_warp_id);
        if (commit_done !== 1'b1 || commit_warp_id !== 3'd4) begin
            errors++;
            $display("FAIL | expected commit_done = 1, warp_id = 4");
        end
        clear_write();

        // Warp 7 completing fully after Warp 0's first few cycles
        do_write(3'd0);
        do_write(3'd0);
        $display("(Warp 0 at cycle 1 before warp 7 starts): commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end
        clear_write();

        do_write(3'd7);
        do_write(3'd7);
        do_write(3'd7);
        do_write(3'd7);
        $display("Warp 7 cycle 3 (full instruction while Warp 0 sits at cycle 1): commit_done = %0b commit_warp_id = %0d",
                commit_done, commit_warp_id);
        if (commit_done !== 1'b1 || commit_warp_id !== 3'd7) begin
            errors++;
            $display("FAIL | expected commit_done = 1, warp_id = 7");
        end
        clear_write();

        do_write(3'd0);
        $display("Warp 0 cycle 2: commit_done = %0b", commit_done);
        if (commit_done !== 1'b0) begin errors++; $display("FAIL | expected 0"); end

        do_write(3'd0);
        $display("warp 0 cycle 3: commit_done = %0b commit_warp_id = %0d", commit_done, commit_warp_id);
        if (commit_done !== 1'b1 || commit_warp_id !== 3'd0) begin
            errors++;
            $display("FAIL | expected commit_done = 1, warp_id = 0");
        end
        clear_write();

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule