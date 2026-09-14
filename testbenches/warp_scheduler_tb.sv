`timescale 1ns/1ps
module tb_warp_scheduler;
    localparam int NUM_WARPS = 8;

    logic clk, reset;
    logic kernel_start;
    logic [2:0] num_warps;
    logic commit_done;
    logic [2:0] commit_warp_id;
    logic [NUM_WARPS-1:0] push2_done;
    logic coalescing_busy;
    logic [1:0] sub_warp_cycle;
    logic sub_warp_valid;
    logic done_detect;

    logic fetch_valid;
    logic buffer_full;

    logic [2:0] curr_warp;
    logic [2:0] next_warp;
    logic issue_valid;
    logic kernel_done;

    logic [2:0] saved_curr_warp;

    int pass_count = 0;
    int fail_count = 0;

    sub_warp_counter sub_counter (
        .clk(clk),
        .reset(reset),
        .fetch_valid(fetch_valid),
        .buffer_full(buffer_full),
        .sub_warp_cycle(sub_warp_cycle),
        .sub_warp_valid(sub_warp_valid)
    );

    warp_scheduler #(.NUM_WARPS(NUM_WARPS)) dut (
        .clk(clk),
        .reset(reset),
        .kernel_start(kernel_start),
        .num_warps(num_warps),
        .commit_done(commit_done),
        .commit_warp_id(commit_warp_id),
        .push2_done(push2_done),
        .coalescing_busy(coalescing_busy),
        .sub_warp_cycle(sub_warp_cycle),
        .sub_warp_valid(sub_warp_valid),
        .done_detect(done_detect),
        .curr_warp(curr_warp),
        .next_warp(next_warp),
        .issue_valid(issue_valid),
        .kernel_done(kernel_done)
    );

    always #5 clk = ~clk;

    // tick to go past the posedge of the clock and give the registers #1 to settle
    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic do_reset();
        reset = 1'b1;
        kernel_start = 1'b0;
        num_warps = 3'd0;
        commit_done = 1'b0;
        commit_warp_id = 3'd0;
        push2_done = '0;
        coalescing_busy = 1'b0;
        fetch_valid = 1'b1;
        buffer_full = 1'b0;
        done_detect = 1'b0;
        tick();
        tick();
        reset = 1'b0;
    endtask

    task automatic launch(input [2:0] n);
        num_warps = n;
        kernel_start = 1'b1;
        tick();
        kernel_start = 1'b0;
    endtask


    task automatic step(input int n);
        repeat (n) tick();
    endtask


    // set sub_warp_cycle == 0 where the next warp is selected
    task automatic to_cycle0();
        while (sub_warp_cycle != 2'd0)
            tick();
    endtask


    // land one tick past that decision, to update curr_warp/next_warp/issue_valid
    task automatic to_decision();
        to_cycle0();
        tick();
    endtask

    task automatic pulse_commit(input [2:0] wid);
        commit_done = 1'b1;
        commit_warp_id = wid;
        tick();
        commit_done = 1'b0;
    endtask

    task automatic pulse_push2(input [2:0] wid);
        push2_done[wid] = 1'b1;
        tick();
        push2_done[wid] = 1'b0;
    endtask


    task automatic check_eq(
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual === expected) begin
            $display("PASS | got = %0d", actual);
            pass_count++;
        end else begin
            $display("FAIL | got = %0d, expected %0d", actual, expected);
            fail_count++;
        end
    endtask


    initial begin
        clk = 0;
        do_reset();
        $display("\nCheck curr_warp, next_warp, and issue_valid after reset");
        check_eq(curr_warp, 3'd0);
        check_eq(next_warp, 3'd0);
        check_eq(issue_valid, 1'b0);

        launch(4); // launch 4 warps (warps 0-3 ready, 4-7 finished immediately, kernel not done)
        $display("\nCheck ready, finished, and kernel_done after launching 4 warps");
        check_eq(dut.ready, 8'b0000_1111);
        check_eq(dut.finished, 8'b1111_0000);
        check_eq(kernel_done, 1'b0);

        to_cycle0();
        for (int i = 0; i < 40; i++) begin
            tick();
            if (next_warp > 3) begin
                $display("\nFAIL | next_warp = %0d outside active range (num_warps = 4)",
                         next_warp);
                fail_count++;
            end
        end
        $display("\nPASS | next_warp stayed in 0-3 over 40 cycles");
        pass_count++;

        // with nothing ever committing, all 4 warps are not ready
        to_cycle0();
        step(16); // 4 x 4 cycles, one warp is issued every 4 cycles
        to_decision();
        $display("\nissue_valid low once all 4 warps issued and none committed");
        check_eq(issue_valid, 1'b0);

        // commit_done for warp 0 fires while sub_warp_cycle == 0
        // freed warp 0 should now be picked
        to_cycle0();
        pulse_commit(3'd0);
        $display("\ncommit_done visible same cycle it fires at cycle 0");
        check_eq(next_warp, 3'd0);
        check_eq(issue_valid, 1'b1);

        // push2_done for warp 2 fires at sub_warp_cycle == 0
        // same pattern as commit_done
        // freed warp 2 should now be picked
        to_cycle0();
        pulse_push2(3'd2);
        $display("\npush2_done[2] visible same cycle it fires");
        check_eq(next_warp, 3'd2);
        check_eq(issue_valid, 1'b1);

        // GTO greedy: keep re-freeing one fixed warp every span, both
        // curr_warp and next_warp should converge onto it and stay there
        do_reset();
        launch(4);
        to_cycle0();
        step(16);
        for (int i = 0; i < 8; i++) begin
            to_cycle0();
            pulse_commit(3'd1);
            $display("\nnext_warp should be 1 now that its previous instruction was committed");
            check_eq(next_warp, 3'd1);
        end
        to_decision();
        $display("\ncurr_warp gets set to warp 1 a span after next_warp");
        check_eq(curr_warp, 3'd1);

        // Test buffer_full stalling sub_warp_counter
        do_reset();
        launch(3);
        to_cycle0();
        step(1); // move from cycle 0 to cycle 1
        saved_curr_warp = curr_warp;

        $display("\nbuffer_full stalls sub-warp counter");
        $display("sub_warp_cycle should be 1 before stall");
        check_eq(sub_warp_cycle, 2'd1);
        buffer_full = 1'b1;
        tick();

        $display("\nsub_warp_counter should freeze at cycle 1");
        check_eq(sub_warp_cycle, 2'd1);
        $display("sub_warp_valid should be 0 while buffer is full");
        check_eq(sub_warp_valid, 1'b0);
        tick();

        $display("\nsub_warp_counter should remain frozen");
        check_eq(sub_warp_cycle, 2'd1);

        $display("\nscheduler should not make a new decision while stalled");
        check_eq(curr_warp, saved_curr_warp);

        buffer_full = 1'b0;
        tick();

        $display("\nsub_warp_counter should resume after buffer is no longer full");
        check_eq(sub_warp_cycle, 2'd2);
        $display("sub_warp_valid should be valid again");
        check_eq(sub_warp_valid, 1'b1);

        // curr_warp catches up to warp_scheduler a span later
        do_reset();
        launch(2);
        to_cycle0();
        step(4);
        to_cycle0();
        pulse_commit(3'd0);
        $display("next_warp reflects the freshly committed warp 0");
        check_eq(next_warp, 3'd0);
        step(4);
        $display("curr_warp catches up one span later");
        check_eq(curr_warp, 3'd0);

        // done_detect: excludes curr_warp from ready_mask the same cycle,
        do_reset();
        launch(1);
        to_cycle0();
        step(4);
        to_cycle0();
        done_detect = 1'b1;
        #1; // sample ready_mask combinationally, before the clock edge
        $display("ready_mask[curr_warp] forced 0 same-cycle on done_detect");
        check_eq(dut.ready_mask[curr_warp], 1'b0);
        tick();
        done_detect = 1'b0;
        $display("no other warp ready -> bubble this cycle");
        check_eq(issue_valid, 1'b0);
        $display("kernel_done set once sole warp finishes");
        check_eq(kernel_done, 1'b1);

        $display("\n=== %0d passed, %0d failed ===",
                 pass_count, fail_count);

        $finish;
    end

    initial begin
        #100000;
        $display("FAIL | testbench timeout");
        $finish;
    end
endmodule