module special_reg_unit # (
    parameter [2:0] LANE_NUM // number of lane instance (0-7)
) (
    input logic [2:0] warp_id_in,
    input logic [1:0] sub_warp_cycle,

    output logic block_id,
    output logic [2:0] warp_id_out,
    output logic [4:0] thread_id
);
    assign block_id = warp_id_in[2]; // 1 if warp_id >= 4, 0 otherwise
    assign warp_id_out = warp_id_in;
    assign thread_id = ({3'b0, sub_warp_cycle} << 3) + LANE_NUM;
endmodule