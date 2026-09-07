module commit_tracker (
    input logic clk,
    input logic reset,

    input logic rf_write_enable,
    input logic [2:0] rf_write_warp_id, // rf_write_addr[9:7]
    
    output logic commit_done,
    output logic [2:0] commit_warp_id
);
    logic [1:0] count_q [0:7]; // wrap around counter to 4

    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 8; i = i + 1)
                count_q[i] <= 2'd0;
            commit_done <= 1'b0;
            commit_warp_id <= 3'd0;
        end else begin
            commit_done <= 1'b0;
            if (rf_write_enable) begin
                if (count_q[rf_write_warp_id] == 2'd3) begin
                    count_q[rf_write_warp_id] <= 2'd0;
                    commit_done <= 1'b1;
                    commit_warp_id <= rf_write_warp_id;
                end else begin
                    count_q[rf_write_warp_id] <= count_q[rf_write_warp_id] + 1'b1;
                end
            end
        end
    end
endmodule