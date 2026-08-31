`timescale 1ns/1ps
module fp32_fma_tb;
    // Declare DUT (Design Under Test) inputs and outputs
    reg clk, reset, valid_in;
    reg [31:0] src1, src2, src3;
    wire [31:0] result;
    wire valid_out;

    integer errors = 0;
    integer tests = 0;

    // Instantiate DUT
    fp32_fma dut (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        .src1(src1),
        .src2(src2),
        .src3(src3),
        .result(result),
        .valid_out(valid_out)
    );

    always #5 clk = ~clk;

    task automatic check_case(
        input [31:0] a, b, c, expected
    );
        begin
            src1 = a;
            src2 = b;
            src3 = c;
            valid_in = 1'b1;
            #1;
            tests = tests + 1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL | a = %h b = %h c = %h | expected = %h got = %h",
                        a, b, c, expected, result);
            end else begin
                $display("PASS | a = %h b = %h c = %h | result=%h", 
                        a, b, c, result);
            end
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        valid_in = 0;
        src1 = 0; src2 = 0; src3 = 0;
        #10 reset = 0;

        // Case 1: 3.0 * 2.0 + 1.5 = 7.5
        // 3.0  = 0_10000000_10000000000000000000000 = 32'h40400000
        // 2.0  = 0_10000000_00000000000000000000000 = 32'h40000000
        // 1.5  = 0_01111111_10000000000000000000000 = 32'h3FC00000
        // 7.5  = 0_10000001_11100000000000000000000 = 32'h40F00000
        check_case(32'h40400000, 32'h40000000, 32'h3FC00000, 32'h40F00000);

        // Case 2: 3.0 * 2.0 + (-1.5) = 4.5
        // 3.0  = 0_10000000_10000000000000000000000 = 32'h40400000
        // 2.0  = 0_10000000_00000000000000000000000 = 32'h40000000
        // -1.5 = 32'hBFC00000
        // 4.5  = 0_10000001_00100000000000000000000 = 32'h40900000
        check_case(32'h40400000, 32'h40000000, 32'hBFC00000, 32'h40900000);

        // Case 3: 1.0 * 1.0 + (-1.0) = 0.0
        // 1.0  = 0_01111111_00000000000000000000000 = 32'h3F800000
        // -1.0 = 1_01111111_00000000000000000000000 = 32'hBF800000
        // 0.0  = 
        check_case(32'h3F800000, 32'h3F800000, 32'hBF800000, 32'h00000000);

        // Case 4: 1.5 * 1.5 + 0.0 = 2.25 (product overflows past 2.0)
        // 2.25 = 0_10000000_00100000000000000000000 = 32'h40100000
        check_case(32'h3FC00000, 32'h3FC00000, 32'h00000000, 32'h40100000);

        // Case 5: src1 negative, src2 positive
        // -3.0 * 2.0 + 1.5 = -6.0 + 1.5 = -4.5
        // -3.0 = 0xC0400000, 2.0 = 0x40000000, 1.5 = 0x3FC00000
        // -4.5 = 1_10000001_00100000000000000000000 = 0xC0900000
        check_case(32'hC0400000, 32'h40000000, 32'h3FC00000, 32'hC0900000);

        // --- Case 6: src1 positive, src2 negative ---
        // 3.0 * -2.0 + 1.5 = -6.0 + 1.5 = -4.5 (same result, different sign combo path)
        // -2.0 = 0xC0000000
        check_case(32'h40400000, 32'hC0000000, 32'h3FC00000, 32'hC0900000);

        // --- Case 7: both multiplicands negative -> product sign flips back to positive ---
        // -3.0 * -2.0 + 1.5 = 6.0 + 1.5 = 7.5
        check_case(32'hC0400000, 32'hC0000000, 32'h3FC00000, 32'h40F00000);

        // --- Case 8: both multiplicands negative, addend also negative ---
        // -3.0 * -2.0 + (-1.5) = 6.0 - 1.5 = 4.5
        // -1.5 = 0xBFC00000
        // 4.5 = 0_10000001_00100000000000000000000 = 0x40900000
        check_case(32'hC0400000, 32'hC0000000, 32'hBFC00000, 32'h40900000);

        // --- Case 9: negative multiplicand, product bigger than addend, addend positive,
        //             product negative -> exercises mul_ge_addend picking the *negative* sign ---
        // -3.0 * 2.0 + 0.5 = -6.0 + 0.5 = -5.5
        // 0.5 = 0x3F000000
        // -5.5 = -(1.375 x 2^2), sign=1, exp=129, mantissa=011000...0
        // -5.5 = 1_10000001_01100000000000000000000 = 0xC0B00000
        check_case(32'hC0400000, 32'h40000000, 32'h3F000000, 32'hC0B00000);

        $display("---------------------------------------------");
        $display("Tests: %0d  Errors: %0d", tests, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule