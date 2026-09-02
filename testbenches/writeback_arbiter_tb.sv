module writeback_arbiter_tb;
    reg clk, reset;
    reg [31:0] alu_data, fma_data, lsu_data;
    reg [9:0]  alu_addr, fma_addr, lsu_addr;
    reg alu_valid, fma_valid, lsu_valid;

    wire [9:0]  rf_write_addr;
    wire [31:0] rf_write_data;
    wire rf_write_enable;
    wire alu_full, fma_full, lsu_full;

    integer errors = 0;
    integer tests = 0;

    writeback_arbiter dut (
        .clk(clk),
        .reset(reset),

        .alu_data(alu_data),
        .fma_data(fma_data),
        .lsu_data(lsu_data),

        .alu_addr(alu_addr),
        .fma_addr(fma_addr),
        .lsu_addr(lsu_addr),
        
        .alu_valid(alu_valid),
        .fma_valid(fma_valid),
        .lsu_valid(lsu_valid),

        .rf_write_addr(rf_write_addr),
        .rf_write_data(rf_write_data),
        .rf_write_enable(rf_write_enable),
        
        .alu_full(alu_full),
        .fma_full(fma_full),
        .lsu_full(lsu_full)
    );

    always #5 clk = ~clk;

    task automatic drive(
        input a_v, input [9:0] a_a, input [31:0] a_d,
        input f_v, input [9:0] f_a, input [31:0] f_d,
        input l_v, input [9:0] l_a, input [31:0] l_d
    );
        begin
            alu_valid = a_v; alu_addr = a_a; alu_data = a_d;
            fma_valid = f_v; fma_addr = f_a; fma_data = f_d;
            lsu_valid = l_v; lsu_addr = l_a; lsu_data = l_d;
            #1; // let combinational grant/mux settle
        end
    endtask

    task automatic check(
        input exp_en, input [9:0] exp_addr, input [31:0] exp_data
    );
        begin
            tests = tests + 1;
            if (rf_write_enable !== exp_en ||
                (exp_en && (rf_write_addr !== exp_addr || rf_write_data !== exp_data))) begin
                errors = errors + 1;
                $display("FAIL | expected: en = %b addr = %h data = %h) | got: en = %b addr = %h data = %h\n",
                        rf_write_enable, rf_write_addr, rf_write_data,
                        exp_en, exp_addr, exp_data);
            end else begin
                $display("PASS | en = %b addr = %h data = %h\n",
                        rf_write_enable, rf_write_addr, rf_write_data);
            end
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1; // settle after clock edge
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        alu_valid = 0; alu_addr = 0; alu_data = 0;
        fma_valid = 0; fma_addr = 0; fma_data = 0;
        lsu_valid = 0; lsu_addr = 0; lsu_data = 0;
        tick(); tick();
        reset = 0;

        // Case 1: single ALU result
        $display("Single ALU result");
        drive(1, 10'h001, 32'hAAAA0001,  0,0,0,  0,0,0);
        check(1, 10'h001, 32'hAAAA0001);
        tick();

        $display("Idle after single ALU");
        drive(0,0,0, 0,0,0, 0,0,0);
        check(0, 0, 0);
        tick();

        // Case 2: LSU and ALU both valid same cycle
        // (LSU should win, ALU should be placed in its buffer)
        $display("LSU and ALU high at the same time, LSU wins over ALU");
        drive(1, 10'h002, 32'h11110002,  0,0,0,  1, 10'h003, 32'h22220003);
        check(1, 10'h003, 32'h22220003);
        tick();

        // Next cycle: nothing new valid
        // ALU's buffered entry should now win
        $display("Buffered ALU drains");
        drive(0,0,0, 0,0,0, 0,0,0);
        check(1, 10'h002, 32'h11110002);
        tick();

        $display("Idle after draining ALU result");
        drive(0,0,0, 0,0,0, 0,0,0);
        check(0, 0, 0);
        tick();

        // Case 3: all three valid same cycle
        // (LSU wins, FMA and ALU should both be placed in their respective buffers)
        $display("All three sources are valid, LSU wins");
        drive(1, 10'h004, 32'h000000A4, 1, 10'h005, 32'h000000F5, 1, 10'h006, 32'h00000006);
        check(1, 10'h006, 32'h00000006);
        tick();

        // FMA should drain next (higher priority than ALU among buffered)
        $display("Buffered FMA drains before ALU");
        drive(0,0,0, 0,0,0, 0,0,0);
        check(1, 10'h005, 32'h000000F5);
        tick();

        $display("Buffered ALU drains last");
        drive(0,0,0, 0,0,0, 0,0,0);
        check(1, 10'h004, 32'h000000A4);
        tick();

        $display("---------------------------------------------");
        $display("Tests: %0d  Errors: %0d", tests, errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end
endmodule