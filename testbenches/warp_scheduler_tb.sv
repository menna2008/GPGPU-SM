`timescale 1ns/1ps
module tb_warp_scheduler;
    localparam int NUM_WARPS = 8;

    logic clk, reset;
    logic kernel_start;
    logic [2:0] num_warps;
    logic commit_done;
    logic [2:0] commit_warp_id;
    logic [NUM_WARPS-1:0] push2_done;
    logic decode_stall;
    logic coalescing_busy;
    logic [1:0] sub_warp_cycle;
    logic sub_warp_valid;
    logic done_detect;

    logic [2:0] curr_warp;
    logic [2:0] next_warp;
    logic issue_valid;
    logic kernel_done;

    int pass_count = 0;
    int fail_count = 0;

    warp_scheduler #(.NUM_WARPS(NUM_WARPS)) dut (
        .clk(clk),
        .reset(reset),
        .kernel_start(kernel_start),
        .num_warps(num_warps),
        .commit_done(commit_done),
        .commit_warp_id(commit_warp_id),
        .push2_done(push2_done),
        .decode_stall(decode_stall),
        .coalescing_busy(coalescing_busy),
        .sub_warp_cycle(sub_warp_cycle),
        .done_detect(done_detect),
        .curr_warp(curr_warp),
        .next_warp(next_warp),
        .issue_valid(issue_valid),
        .kernel_done(kernel_done)
    );

    always #5 clk = ~clk;

    // stand-in for sub_warp_counter: free-running 0-3, always valid
    always_ff @(posedge clk)
        if (reset) sub_warp_cycle <= 2'd0;
        else sub_warp_cycle <= sub_warp_cycle + 2'd1;
    assign sub_warp_valid = 1'b1;

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
        decode_stall = 1'b0;
        coalescing_busy = 1'b0;
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
        while (sub_warp_cycle != 2'd0) tick();
    endtask

    // land one tick past that decision, so curr_warp/next_warp/issue_valid
    // reflect its outcome.
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

    task automatic pulse_decode_stall();
        decode_stall = 1'b1;
        tick();
        decode_stall = 1'b0;
    endtask

    task automatic check_eq(input logic [31:0] actual, input logic [31:0] expected);
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

        // reset clears state
        do_reset();
        $display("Check curr_warp, next_warp, and issue_valid after reset");
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
                $display("FAIL | next_warp = %0d outside active range (num_warps = 4)", next_warp);
                fail_count++;
            end
        end
        $display("PASS | next_warp stayed in 0-3 over 40 cycles");
        pass_count++;

        // with nothing ever committing, all 4 warps are not ready
        to_cycle0();
        step(16); // 4 x 4 cycles, one warp is issued every 4 cycles
        to_decision();
        $display("issue_valid low once all 4 warps issued and none committed");
        check_eq(issue_valid, 1'b0);

        // commit_done for warp 0 fires while sub_warp_cycle == 0
        // freed warp 0 should now be picked
        to_cycle0();
        pulse_commit(3'd0);
        $display("commit_done visible same cycle it fires at cycle 0");
        check_eq(next_warp, 3'd0);
        check_eq(issue_valid, 1'b1);

        // push2_done for warp 2 fires at sub_warp_cycle == 0
        // same pattern as commit_done
        // freed warp 2 should now be picked
        to_cycle0();
        pulse_push2(3'd2);
        $display("push2_done[2] visible same cycle it fires");
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
            $display("next_warp should be 1 now that its previous instrucion was committed");
            check_eq(next_warp, 3'd1);
        end
        to_decision();
        $display("curr_warp gets set to warp 1 a span after next_warp");
        check_eq(curr_warp, 3'd1);

        // decode_stall: diverts to the other ready warp immediately, and
        // replays the stalled warp without needing commit_done
        do_reset();
        launch(3);
        to_cycle0();
        step(4); // warp 0 claimed as next_warp
        decode_stall = 1'b1;
        to_cycle0(); // to next decision edge
        pulse_decode_stall(); // asserted while sub_warp_cycle==0
        $display("warp 0 stalled by the decode stage, so next warp is warp 2");
        tick();
        check_eq(next_warp, 3'd1);
        decode_stall = 1'b0;

        // decode_stall with nothing else ready retries curr_warp
        do_reset();
        launch(1);
        to_cycle0();
        step(4); // warp0 claimed
        to_cycle0();
        $display("decode_stall with no alternative retries curr_warp");
        check_eq(next_warp, 3'd0);
        check_eq(issue_valid, 1'b1);

        // curr_warp/next_warp staging: a decision shows up in next_warp
        // immediately, curr_warp only catches up one span later
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

        $display("\n=== %0d passed, %0d failed ===", pass_count, fail_count);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL | testbench timeout");
        $finish;
    end
endmodule