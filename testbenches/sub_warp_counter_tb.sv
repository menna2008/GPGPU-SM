`timescale 1ns/1ps
module sub_warp_counter_tb;
    logic clk, reset;
    logic fetch_valid;
    logic buffer_full;
    logic [1:0] sub_warp_cycle;
    logic sub_warp_valid;

    int errors = 0;
    int checks = 0;

    sub_warp_counter DUT (
        .clk(clk),
        .reset(reset),
        .fetch_valid(fetch_valid),
        .buffer_full(buffer_full),
        .sub_warp_cycle(sub_warp_cycle),
        .sub_warp_valid(sub_warp_valid)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        fetch_valid = 0;
        buffer_full = 0;

        // reset state: sub_warp_cycle is 3, (nothing latched yet)
        @(posedge clk); @(posedge clk);
        #1;
        $display("post-reset: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0");
        end

        reset = 0;

        // sub_warp_cycle stays 3 while fetch_valid is low
        @(posedge clk); #1;
        $display("hold at 3, fetch_valid = 0 (a): cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0");
        end

        // sub_warp_cycle goes to 0 when fetch_valid is high
        @(negedge clk);
        fetch_valid = 1;
        @(posedge clk);
        #1;
        fetch_valid = 0;
        $display("first instruction latched: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd0 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 0 valid = 1");
        end

        // sub_warp_cycle freely increments every cycle until it reaches 3
        @(posedge clk); #1;
        $display("advance to cycle 1: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd1 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 1 valid = 1");
        end

        @(posedge clk); #1;
        $display("advance to cycle 2: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd2 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 2 valid = 1");
        end

        @(posedge clk); #1;
        $display("advance to cycle 3: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 1");
        end

        // held at 3 again (no new fetch ready)
        @(posedge clk); #1;
        $display("held at 3 (fetch_valid = 0): cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0");
        end

        @(posedge clk); #1;
        $display("held at 3 again (fetch_valid=0): cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0");
        end

        // sub_warp_cycle goes back down to 0 when fetch_valid becomes high
        @(negedge clk);
        fetch_valid = 1;
        @(posedge clk);
        #1;
        fetch_valid = 0;
        $display("second instruction latched: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd0 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 0 valid = 1");
        end

        // Instruction becomes available (fetch_valid == 1) after each cycle from 0 -> 3
        @(posedge clk); #1;
        $display("cycle 1: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd1 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 1 valid = 1");
        end

        @(posedge clk); #1;
        $display("cycle 2: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd2 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 2 valid = 1");
        end

        @(negedge clk);
        fetch_valid = 1;
        @(posedge clk);
        #1;
        checks++;
        $display("cycle 3, fetch_valid is also high: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 1");
        end

        @(posedge clk); #1;
        $display("sub_warp_cycle goes down to 0 immediately since fetch is valid: cycle = %0d valid = %0b",
                sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd0 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 0 valid = 1");
        end
        @(negedge clk);
        fetch_valid = 0;

        // mid-loop reset
        @(posedge clk); #1; // cycle 1
        reset = 1;
        @(posedge clk); #1;
        $display("mid-loop reset: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0");
        end
        reset = 0;

        // Set fetch_valid to 1, sub_warp_cycle goes back down to 0
        @(negedge clk);
        fetch_valid = 1;
        @(posedge clk); #1; // cycle 0
        fetch_valid = 0;
        @(posedge clk); #1; // cycle 1
        @(posedge clk); #1; // cycle 2
        @(posedge clk); #1; // cycle 3
        $display("cycle 3: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 1");
        end

        for (int k = 0; k < 5; k++) begin
            @(posedge clk); #1;
            checks++;
            $display("hold while fetch_valid == 0: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
            if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
                errors++;
                $display("FAIL | expected cycle = 3 valid = 0");
            end
        end

        @(negedge clk);
        fetch_valid = 1;
        @(posedge clk); #1;
        fetch_valid = 0;
        $display("fetch_valid is finally high, sub_warp_cycle goes down to cycle 0: cycle = %0d valid = %0b",
                sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd0 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 0 valid = 1");
        end

        // buffer_full: pause mid-span at cycle 1, resume from cycle 1
        @(posedge clk); #1; // cycle 1
        $display("cycle 1 before buffer_full: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd1 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 1 valid = 1");
        end

        @(negedge clk);
        buffer_full = 1;
        @(posedge clk); #1; // buffer_full asserts while already sitting at cycle 1 --
                            // this is a second consecutive cycle at the same value
                            // (not an arrival), so it reads invalid immediately, same
                            // rule as the second consecutive cycle held at 3.
        checks++;
        $display("buffer_full asserts, already sitting at cycle 1: cycle = %0d valid = %0b",
                sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd1 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 1 valid = 0");
        end

        for (int k = 0; k < 4; k++) begin
            @(posedge clk); #1;
            checks++;
            $display("held at cycle 1 (buffer_full): cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
            if (sub_warp_cycle !== 2'd1 || sub_warp_valid !== 1'b0) begin
                errors++;
                $display("FAIL | expected cycle = 1 valid = 0");
            end
        end

        @(negedge clk);
        buffer_full = 0;
        @(posedge clk); #1;
        $display("buffer_full clears, resumes to cycle 2 (not restarted to 0): cycle = %0d valid = %0b",
                sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd2 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 2 valid = 1");
        end

        // buffer_full asserting at cycle 3, fetch_valid already low
        // both hold reasons active at once, both must clear before advancing
        @(posedge clk); #1; // cycle 3
        $display("advance to cycle 3: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 1");
        end

        @(negedge clk);
        buffer_full = 1;
        @(posedge clk); #1;
        checks++;
        $display("held at 3, buffer_full=1 fetch_valid=0: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0");
        end

        // buffer_full clears but fetch_valid is still low
        @(negedge clk);
        buffer_full = 0;
        @(posedge clk); #1;
        checks++;
        $display("buffer_full clears but fetch_valid still 0: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0");
        end

        // now fetch_valid arrives, cycle should finally advance to 0
        @(negedge clk);
        fetch_valid = 1;
        @(posedge clk); #1;
        fetch_valid = 0;
        $display("fetch_valid finally arrives: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd0 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 0 valid = 1");
        end

        // buffer_full held for many cycles in a row so cycle held and becomes invalid
        @(posedge clk); #1; // cycle 1
        @(negedge clk);
        buffer_full = 1;
        for (int k = 0; k < 8; k++) begin
            @(posedge clk); #1;
            checks++;
            $display("held at cycle 1, cycle %0d of hold: cycle = %0d valid = %0b", k, sub_warp_cycle, sub_warp_valid);
            if (sub_warp_cycle !== 2'd1 || sub_warp_valid !== 1'b0) begin
                errors++;
                $display("FAIL | expected cycle = 1 valid = 0");
            end
        end
        @(negedge clk);
        buffer_full = 0;
        @(posedge clk); #1;
        $display("long buffer_full hold clears, resumes to cycle 2: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd2 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 2 valid = 1");
        end

        // buffer_full already high at cycle 3 before next instruction
        @(posedge clk); #1; // cycle 3 (advance from 2)
        $display("advance to cycle 3 cleanly: cycle = %0d valid = %0b", sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 1");
        end
        @(negedge clk);
        fetch_valid = 1;
        buffer_full = 1;
        @(posedge clk); #1;
        checks++;
        $display("buffer_full already high blocks the 3->0 arrival entirely: cycle = %0d valid = %0b",
                sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd3 || sub_warp_valid !== 1'b0) begin
            errors++;
            $display("FAIL | expected cycle = 3 valid = 0 (blocked, not advanced to 0)");
        end
        @(negedge clk);
        buffer_full = 0;
        @(posedge clk); #1;
        fetch_valid = 0;
        $display("buffer_full clears, now reset to 0: cycle = %0d valid = %0b",
                sub_warp_cycle, sub_warp_valid);
        if (sub_warp_cycle !== 2'd0 || sub_warp_valid !== 1'b1) begin
            errors++;
            $display("FAIL | expected cycle = 0 valid = 1");
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule