module result_fifo #(
    parameter int DEPTH = 2,
    parameter int COUNT_DEPTH = $clog2(DEPTH+1)
) (
    input wire clk,
    input wire reset,

    input wire push,
    input wire [9:0] push_addr,
    input wire [31:0] push_data,

    input wire pop,

    output wire [9:0] head_addr,
    output wire [31:0] head_data,
    output wire empty,
    output wire full
);
    reg [9:0] addr_q [0:DEPTH-1];
    reg [31:0] data_q [0:DEPTH-1];
    reg [COUNT_DEPTH-1:0] count_q;

    integer i;

    assign head_addr = addr_q[0];
    assign head_data = data_q[0];
    assign empty = ~|count_q; // (count_q == 0)
    assign full = (count_q == DEPTH);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            count_q <= '0;
        end else begin
            if (pop && !push) begin
                // pop only, so shift only and decrement counter
                for (i = 0; i < DEPTH-1; i = i + 1) begin
                    addr_q[i] <= addr_q[i+1];
                    data_q[i] <= data_q[i+1];
                end
                count_q <= count_q - 1'b1;
            end else if (push && !pop) begin
                // push only, so add new entry at tail and increment counter
                addr_q[count_q] <= push_addr;
                data_q[count_q] <= push_data;
                count_q <= count_q + 1'b1;
            end else if (push && pop) begin
                // push and pop, so shift down by one add new entry at tail
                for (i = 0; i < DEPTH-1; i = i + 1) begin
                    addr_q[i] <= addr_q[i+1];
                    data_q[i] <= data_q[i+1];
                end
                addr_q[count_q-1] <= push_addr;
                data_q[count_q-1] <= push_data;
                // count_q unchanged
            end
            // no push and no pop means leave FIFO and count unchanged
        end
    end
endmodule
