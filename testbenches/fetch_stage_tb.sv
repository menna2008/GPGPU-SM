module fetch_stage_tb;
    logic clk, reset;
    logic [2:0] next_warp;
    logic [31:0] top_pc, recon_pc;
    logic consume, icache_ready;
    logic [127:0] icache_data;

    logic icache_req_valid;
    logic [31:0] icache_addr;
    logic fetch_valid;
    logic [31:0] instr, instr_pc;

    int errors = 0;
    int tests = 0;

    fetch_stage DUT (
        .clk(clk),
        .reset(reset),
        .next_warp(next_warp),
        .top_pc(top_pc),
        .recon_pc(recon_pc),
        .consume(consume),
        .icache_ready(icache_ready),
        .icache_data(icache_data),
        .icache_req_valid(icache_req_valid),
        .icache_addr(icache_addr),
        .fetch_valid(fetch_valid),
        .instr(instr),
        .instr_pc(instr_pc)
    );

    always #5 clk = ~clk;

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_req(input exp_valid, input [31:0] exp_addr);
        tests++;
        if (icache_req_valid !== exp_valid || icache_addr !== exp_addr) begin
            errors++;
            $display("FAIL | expected req_valid = %0b addr = %0h | got req_valid = %0b addr = %0h",
                exp_valid, exp_addr, icache_req_valid, icache_addr);
        end else begin
            $display("PASS | req_valid = %0b addr = %0h", icache_req_valid, icache_addr);
        end
    endtask

    task automatic check(input [31:0] exp_instr, exp_pc, input exp_valid);
        tests++;
        if (instr !== exp_instr || instr_pc !== exp_pc || fetch_valid !== exp_valid) begin
            errors++;
            $display("FAIL | expected instr = %0d pc = %0h valid = %0b | got instr = %0d pc = %0h valid = %0b",
                exp_instr, exp_pc, exp_valid, instr, instr_pc, fetch_valid);
        end else begin
            $display("PASS | instr = %0d pc = %0h valid = %0b", instr, instr_pc, fetch_valid);
        end
    endtask

    task automatic check_valid(input exp_valid);
        tests++;
        if (fetch_valid !== exp_valid) begin
            errors++;
            $display("FAIL | expected fetch_valid = %0b | got fetch_valid = %0b", exp_valid, fetch_valid);
        end else begin
            $display("PASS | fetch_valid = %0b", fetch_valid);
        end
    endtask

    localparam [31:0] I_A = 32'h0000_0001;
    localparam [31:0] I_B = 32'h0000_0002;
    localparam [31:0] I_C = 32'h0000_0003;
    localparam [31:0] I_D = 32'h0000_0004;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        next_warp = 3'd0;
        top_pc = 32'h1000;
        recon_pc = 32'hFFFF_FFFF;
        consume = 1'b0;
        icache_ready = 1'b0;
        icache_data = '0;

        tick();

        // 0: held in reset
        $display("No request asserted while reset is high");
        check_req(1'b0, 32'h0);

        reset = 1'b0;
        #1;

        // 1: issue on empty buffer, immediately post-reset
        $display("\nIssue fires immediately once reset drops, buffer empty");
        check_req(1'b1, top_pc);

        // 2: same-cycle hit — icache_ready asserted the same instant as the issue
        $display("\nSame-cycle hit: fill_valid fires combinationally, no wait state entered");
        icache_ready = 1'b1;
        icache_data = {I_D, I_C, I_B, I_A};
        #1;
        // fill_valid isn't a DUT output, but we can confirm no spurious wait
        // state by checking the buffer commits on the very next edge with no
        // extra idle cycle in between.
        tick();
        icache_ready = 1'b0;
        icache_data = '0;
        #1;
        check(I_A, top_pc, 1'b1);

        // 3: no re-issue while buffer full
        $display("\nNo re-issue while buffer still full after same-cycle hit");
        check_req(1'b0, top_pc);
        tick();
        check_req(1'b0, top_pc);

        // 4: drain fully, confirm re-issue
        $display("\nRe-issue exactly when buffer drains");
        consume = 1'b1;
        tick();
        check(I_B, top_pc + 32'h4, 1'b1);
        check_req(1'b0, top_pc);
        tick();
        check(I_C, top_pc + 32'h8, 1'b1);
        tick();
        check(I_D, top_pc + 32'hC, 1'b1);
        tick();
        consume = 1'b0;
        #1;
        check_valid(1'b0);
        check_req(1'b1, top_pc);

        // 5: multi-cycle miss on this reissue
        // icache_ready low for several cycles
        // no duplicate request is issued while waiting
        $display("\nNo re-issue while icache_ready stays low across several cycles");
        tick();
        check_req(1'b0, top_pc);
        tick();
        check_req(1'b0, top_pc);
        tick();
        check_req(1'b0, top_pc);

        $display("\nFill commits once icache_ready finally lands");
        icache_data = {I_D, I_C, I_B, I_A};
        icache_ready = 1'b1;
        tick();
        icache_ready = 1'b0;
        check(I_A, top_pc, 1'b1);

        // 6: switch warps only once idle/full (respects the unlatched-next_warp invariant)
        $display("\nSwitching warps produces an independent fetch");
        consume = 1'b1;
        tick(); tick(); tick(); tick();
        consume = 1'b0;
        #1;
        check_valid(1'b0);

        next_warp = 3'd5;
        top_pc = 32'h9000;
        recon_pc = 32'hFFFF_FFFF;
        #1;
        check_req(1'b1, 32'h9000);
        tick();
        icache_data = {I_D, I_C, I_B, I_A};
        icache_ready = 1'b1;
        tick();
        icache_ready = 1'b0;
        check(I_A, 32'h9000, 1'b1);

        $display("tests=%0d errors=%0d", tests, errors);
        $finish;
    end
endmodule