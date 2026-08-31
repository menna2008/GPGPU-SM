module fp32_fma(
    input clk,
    input reset,
    input valid_in,
    input [31:0] src1,
    input [31:0] src2,
    input [31:0] src3,
    output [31:0] result,
    output valid_out
);
    // unpack sources into sign, exponent, and mantissa

    wire sign1, sign2, sign3;
    wire [23:0] mant1, mant2, mant3;
    wire [7:0] exp1, exp2, exp3;

    assign sign1 = src1[31];
    assign sign2 = src2[31];
    assign sign3 = src3[31];

    assign exp1 = src1[30:23];
    assign exp2 = src2[30:23];
    assign exp3 = src3[30:23];

    assign mant1 = {1'b1, src1[22:0]};
    assign mant2 = {1'b1, src2[22:0]};
    assign mant3 = {1'b1, src3[22:0]};

    // Multiply src1 and src2
    wire [47:0] mant_mul;
    wire [8:0] exp_mul;
    wire sign_mul;

    assign mant_mul = mant1 * mant2;
    assign exp_mul = exp1 + exp2 - 127;
    assign sign_mul = sign1 ^ sign2;

    // Normalize the product before alignment
    wire mant_mul_overflow = mant_mul[47];  // 1 if product >= 2.0

    wire [22:0] mant_mul_norm_frac = mant_mul_overflow ? mant_mul[46:24] : mant_mul[45:23];
    wire [23:0] mant_mul_norm = {1'b1, mant_mul_norm_frac};  // always proper 1.xxx, 24 bits

    wire [8:0] exp_mul_norm = mant_mul_overflow ? (exp_mul + 9'd1) : exp_mul;

    // Alignment
    wire product_ge_addened;
    wire signed [8:0] exp_diff, exp_aligned;
    wire [23:0] mant3_aligned, mant_mul_aligned, shift_source;
    wire alignment_guard, alignment_round, alignment_sticky;
    
    assign product_ge_addened = (exp_mul_norm >= exp3);
    assign exp_diff = product_ge_addened ? (exp_mul_norm - exp3) : (exp3 - exp_mul_norm);
    assign shift_source = product_ge_addened ? mant3 : mant_mul_norm;

    assign alignment_guard = (exp_diff >= 1 && exp_diff < 24)
                             ? shift_source[exp_diff-1] : 1'b0;
    
    assign alignment_round = (exp_diff >= 2 && exp_diff < 24)
                             ? shift_source[exp_diff-2] : 1'b0;
    
    assign alignment_sticky = (exp_diff >= 24) ? |shift_source
                              : (exp_diff >= 3) ? |(shift_source & ~(24'hFFFFFF << (exp_diff - 3)))
                              : 1'b0;

    assign mant3_aligned = product_ge_addened
                           ? (exp_diff >= 24) ? 24'b0 : (mant3 >> exp_diff)
                           : mant3;

    assign mant_mul_aligned = product_ge_addened
                           ? mant_mul_norm
                           : (exp_diff >= 24) ? 24'b0 : (mant_mul_norm >> exp_diff);

    assign exp_aligned = product_ge_addened ? exp_mul_norm : exp3;

    // Adding multiplicand and addend
    wire add_sign, same_sign, mul_ge_addend;
    wire [24:0] addition, result_add;
    wire [23:0] subtraction;
    wire [8:0] add_exp;

    wire add_guard  = alignment_guard;
    wire add_round  = alignment_round;
    wire add_sticky = alignment_sticky;

    assign same_sign = (sign3 == sign_mul);
    assign mul_ge_addend = (mant_mul_aligned >= mant3_aligned);

    assign addition = mant_mul_aligned + mant3_aligned;
    assign subtraction = mul_ge_addend
                         ? mant_mul_aligned - mant3_aligned
                         : mant3_aligned - mant_mul_aligned;
    
    assign result_add = same_sign ? addition : {1'b0, subtraction};
    assign add_sign = same_sign
                         ? sign_mul
                         : (mul_ge_addend ? sign_mul : sign3);
    
    assign add_exp = exp_aligned;

    function automatic [4:0] count_leading_zeros(input [23:0] val);
        begin
            casez (val)
                24'b1???????????????????????: count_leading_zeros = 5'd0;
                24'b01??????????????????????: count_leading_zeros = 5'd1;
                24'b001?????????????????????: count_leading_zeros = 5'd2;
                24'b0001????????????????????: count_leading_zeros = 5'd3;
                24'b00001???????????????????: count_leading_zeros = 5'd4;
                24'b000001??????????????????: count_leading_zeros = 5'd5;
                24'b0000001?????????????????: count_leading_zeros = 5'd6;
                24'b00000001????????????????: count_leading_zeros = 5'd7;
                24'b000000001???????????????: count_leading_zeros = 5'd8;
                24'b0000000001??????????????: count_leading_zeros = 5'd9;
                24'b00000000001?????????????: count_leading_zeros = 5'd10;
                24'b000000000001????????????: count_leading_zeros = 5'd11;
                24'b0000000000001???????????: count_leading_zeros = 5'd12;
                24'b00000000000001??????????: count_leading_zeros = 5'd13;
                24'b000000000000001?????????: count_leading_zeros = 5'd14;
                24'b0000000000000001????????: count_leading_zeros = 5'd15;
                24'b00000000000000001???????: count_leading_zeros = 5'd16;
                24'b000000000000000001??????: count_leading_zeros = 5'd17;
                24'b0000000000000000001?????: count_leading_zeros = 5'd18;
                24'b00000000000000000001????: count_leading_zeros = 5'd19;
                24'b000000000000000000001???: count_leading_zeros = 5'd20;
                24'b0000000000000000000001??: count_leading_zeros = 5'd21;
                24'b00000000000000000000001?: count_leading_zeros = 5'd22;
                24'b000000000000000000000001: count_leading_zeros = 5'd23;
                24'b000000000000000000000000: count_leading_zeros = 5'd24; // true zero
                default: count_leading_zeros = 5'd24;
            endcase
        end
    endfunction

    // Noramlize results
    wire overflow, exp_overflow, exp_underflow;
    wire [23:0] result_norm, result_norm_final;
    wire [8:0] result_exp_norm;
    wire [7:0] result_exp_final;
    wire [4:0] lz_count;
    wire is_true_zero;
    wire overflow_new_guard, overflow_new_sticky;

    wire norm_guard, norm_round, norm_sticky;

    assign lz_count = count_leading_zeros(result_add[23:0]);
    assign overflow = result_add[24];
    assign is_true_zero = (!overflow && lz_count[4] && lz_count[3]); // lz_count[4] && lz_count[3] is only 1 if lz_count = 24

    assign result_norm = overflow
                         ? result_add[24:1]
                         : is_true_zero ? 24'b0 : (result_add[23:0] << lz_count);

    assign result_exp_norm = overflow
                             ? (add_exp + 1) :
                             is_true_zero ? 9'b0  : (add_exp - lz_count);
    
    assign exp_underflow = !overflow && (lz_count >= add_exp); // negative (sign bit set on 9-bit) or exactly 0
    assign exp_overflow  = overflow && (result_exp_norm > 9'd255);

    assign overflow_new_guard  = result_add[0];
    assign overflow_new_sticky = add_guard | add_round | add_sticky; // everything previously tracked, OR'd together

    assign result_norm_final = (is_true_zero || exp_underflow) ? 24'b0
                                      : exp_overflow ? 24'b0  // infinity: mantissa forced 0
                                      : result_norm;

    assign result_exp_final = (is_true_zero || exp_underflow) ? 8'b0 : result_exp_norm[7:0]; // overflow is handled after rounding
    
    assign norm_guard  = overflow ? result_add[0] : add_guard;
    assign norm_round  = overflow ? 1'b0 : add_round;
    assign norm_sticky = overflow ? (add_guard | add_round | add_sticky) : add_sticky;

    // Rounding
    wire round_up, rounding_overflow, final_exp_overflow, final_exp_underflow;
    wire [24:0] result_round;
    wire [23:0] result_round_final;
    wire [8:0] result_exp_rounded;

    wire [23:0] result_mant;
    wire [7:0] result_exp;
    
    assign round_up = norm_guard && (norm_round || norm_sticky || result_norm_final[0]);
    assign result_round = result_norm_final + {23'b0, round_up};
    assign rounding_overflow = result_round[24];

    assign result_round_final = rounding_overflow ? {1'b1, 23'b0} : result_round;
    assign result_exp_rounded = rounding_overflow ? ({1'b0, result_exp_final} + 9'd1) : result_exp_final;

    assign final_exp_overflow  = exp_overflow || (!is_true_zero && !exp_underflow && (result_exp_rounded > 9'd255));
    assign final_exp_underflow = exp_underflow;

    assign result_mant = (is_true_zero || final_exp_underflow) ? 24'b0
                                  : final_exp_overflow ? 24'b0
                                  : result_round_final;

    assign result_exp = (is_true_zero || final_exp_underflow) ? 8'b0
                               : final_exp_overflow ? 8'hFF
                               : result_exp_rounded[7:0];

    // Pack normalized results
    assign result = {add_sign, result_exp, result_mant[22:0]};

    assign valid_out = valid_in;
endmodule