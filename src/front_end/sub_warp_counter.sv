module sub_warp_counter(
    input  logic clk,
    input  logic reset,
    input  logic fetch_valid, // from fetch_stage — gates the hold-at-3 → 0 transition
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
            if (~&sub_warp_cycle) sub_warp_cycle <= sub_warp_cycle + 2'd1; // (sub_warp_cycle != 2'b11)
            else if (fetch_valid) sub_warp_cycle <= 2'd0;
        end
    end

    assign sub_warp_valid = ~(&sub_warp_cycle && prev_at_3); // (sub_warp_cycle == 2'b11 && previous cycle also no. 3)
endmodule