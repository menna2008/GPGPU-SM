`timescale 1ns/1ps
module special_reg_unit_tb;
    logic [2:0] warp_id_in;
    logic [1:0] sub_warp_cycle;

    // 8 lanes
    logic block_id [0:7];
    logic [2:0] warp_id_out [0:7];
    logic [4:0] thread_id   [0:7];

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : lane
            special_reg_unit #(.LANE_NUM(i[2:0])) DUT (
                .warp_id_in(warp_id_in),
                .sub_warp_cycle(sub_warp_cycle),
                .block_id(block_id[i]),
                .warp_id_out(warp_id_out[i]),
                .thread_id(thread_id[i])
            );
        end
    endgenerate

    int errors = 0;

    task check(logic [31:0] got, logic [31:0] exp);
        if (got !== exp) begin
            $display("FAIL | got = %0d expected = %0d", got, exp);
            errors++;
        end else begin
            $display("PASS | got = %0d", got);
        end
    endtask

    initial begin
        warp_id_in       = 3'd0;
        sub_warp_cycle    = 2'd0;
        #1;

        // thread_id = lane_number + 8 * sub_warp_cycle
        for (int cycle = 0; cycle < 4; cycle++) begin
            sub_warp_cycle = cycle[1:0];
            #1;
            for (int lane_idx = 0; lane_idx < 8; lane_idx++) begin
                $display("Checking sub_warp_cycle = %0d, lane_idx = %0d", sub_warp_cycle, lane_idx);
                check(thread_id[lane_idx], lane_idx + 8 * cycle);
            end
        end

        // --- wid passthrough: every lane must broadcast the same warp_id_in ---
        sub_warp_cycle = 2'd0;
        for (int warp = 0; warp < 8; warp++) begin
            warp_id_in = warp[2:0];
            #1;
            for (int lane_idx = 0; lane_idx < 8; lane_idx++) begin
                $display("WID passthrough, lane = %0d, warp_id = %0d");
                check(warp_id_out[lane_idx], warp);
            end
        end

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule