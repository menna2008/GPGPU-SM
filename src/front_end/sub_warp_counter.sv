module sub_warp_counter(
    input logic clk,
    input logic reset,
    input logic fetch_valid, // from fetch_stage — hold at 3 instead of resetting to 0 for invalid fetch
    input logic decode_stall,
    output logic [1:0] sub_warp_cycle,
    output logic sub_warp_valid
);
    logic prev_at_3;
    always_ff @(posedge clk) begin
        if (reset) begin
            sub_warp_cycle <= 2'd3;
            prev_at_3 <= 1'b1;
        end else begin
            prev_at_3 <= (sub_warp_cycle == 2'd3);
            // If the last cycle for the current instruction is reached,
            // The counter resets to 0 if there is a valid instruction fetched
            // Otherwise stay at 3 but the cycle becomes invalid to avoid
            // repeat the current instruction

            // If a decode stalled due to full FIFO in writeback_arbiter
            // Warp is switched and the counter is reset to 0 or
            // stays at 3 depending on if the next warp's instruction is fetched
            if (decode_stall || sub_warp_cycle == 2'd3)
                sub_warp_cycle <= fetch_valid ? 2'd0 : 2'd3;
            else
                sub_warp_cycle <= sub_warp_cycle + 2'd1; // (sub_warp_cycle != 2'b11)
        end
    end

    assign sub_warp_valid = ~(&sub_warp_cycle && prev_at_3); // (sub_warp_cycle == 2'b11 && previous cycle also no. 3)
endmodule