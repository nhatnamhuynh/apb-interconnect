`timescale 1ns / 1ps

module tb_addr;
    parameter int unsigned N_SLAVES   = 4;
    parameter int unsigned ADDR_WIDTH = 32;
    parameter int unsigned DATA_WIDTH = 32;
    
    localparam int ALIGN_LSB = $clog2(DATA_WIDTH / 8);
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef addr_t addr_arr_t [N_SLAVES];

    // ham sinh base , size cho bat ki N_Slaves
    function automatic addr_arr_t gen_base_addr();
        addr_arr_t base;
        addr_t step;
        step = (1 << (ADDR_WIDTH - 6)); 
        if (step < (DATA_WIDTH / 8) * 4) step = (DATA_WIDTH / 8) * 4;

        for (int i = 0; i < N_SLAVES; i++) begin
            base[i] = (i + 1) * step;
        end
        return base;
    endfunction

    function automatic addr_arr_t gen_addr_size();
        addr_arr_t size;
        addr_t step, reg_size;
        step = (1 << (ADDR_WIDTH - 6));
        if (step < (DATA_WIDTH / 8) * 4) step = (DATA_WIDTH / 8) * 4;
        
        reg_size = step >> 1; 
        if (reg_size < (DATA_WIDTH / 8)) reg_size = (DATA_WIDTH / 8);

        for (int i = 0; i < N_SLAVES; i++) begin
            size[i] = reg_size;
        end
        return size;
    endfunction

    localparam addr_arr_t SLV_BASE_ADDR = gen_base_addr();
    localparam addr_arr_t SLV_ADDR_SIZE = gen_addr_size();

    logic                          S_PSEL;
    logic [ADDR_WIDTH-1:ALIGN_LSB] S_PADDR; 
    logic [N_SLAVES-1:0]           hit;     
    logic                          no_hit;

    int err_cnt  = 0;
    int pass_cnt = 0;

    apb_address_decoder #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .N_SLAVES      (N_SLAVES),
        .SLV_BASE_ADDR (SLV_BASE_ADDR),
        .SLV_ADDR_SIZE (SLV_ADDR_SIZE)
    ) dut (
        .S_PADDR (S_PADDR),
        .S_PSEL  (S_PSEL),
        .hit     (hit),
        .no_hit  (no_hit)
    );

    function automatic void predict_result(
        input  addr_t               full_addr,
        input  logic                psel,
        output logic [N_SLAVES-1:0] exp_hit,
        output logic                exp_no_hit
    );
        addr_t al_addr;
        al_addr = {full_addr[ADDR_WIDTH-1:ALIGN_LSB], {ALIGN_LSB{1'b0}}};
        exp_hit = '0;

        if (psel) begin
            for (int i = 0; i < N_SLAVES; i++) begin
                if ((al_addr >= SLV_BASE_ADDR[i]) && 
                    (al_addr < (SLV_BASE_ADDR[i] + SLV_ADDR_SIZE[i]))) begin
                    exp_hit[i] = 1'b1;
                end
            end
        end
        exp_no_hit = psel && (~(|exp_hit));
    endfunction

    // check
    task automatic check_code (
        input addr_t full_addr,
        input logic  psel,
        input string case_id
    );
        logic [N_SLAVES-1:0] exp_hit;
        logic                exp_no_hit;
    begin
        predict_result(full_addr, psel, exp_hit, exp_no_hit);

        S_PADDR = full_addr[ADDR_WIDTH-1:ALIGN_LSB];
        S_PSEL  = psel;
        #10; 

        // check chi dc phep 1 hit , ko co floating
        if (!$onehot0(hit) || $isunknown({hit, no_hit})) begin
            $error("[FAIL-ONEHOT/X] %s | hit=%b, no_hit=%b", case_id, hit, no_hit);
            err_cnt++;
        end

        if (hit !== exp_hit || no_hit !== exp_no_hit) begin
            $error("[FAIL] %s | Addr: 0x%0h (Aligned: 0x%0h) | PSEL: %b | Got hit=%b, no_hit=%b | Expected hit=%b, no_hit=%b",
                   case_id, full_addr, S_PADDR, psel, hit, no_hit, exp_hit, exp_no_hit);
            err_cnt++;
        end else begin
            pass_cnt++;
        end
    end
    endtask

    // 3. REQ-DEC-005
    task automatic check_combinational_stability();
        logic [N_SLAVES-1:0] hit_t0, hit_t1;
        logic                no_hit_t0, no_hit_t1;
    begin
        $display(" (REQ-DEC-005");
        // stable or not ?
        S_PADDR = SLV_BASE_ADDR[0][ADDR_WIDTH-1:ALIGN_LSB];
        S_PSEL  = 1'b1;
        #10;
        hit_t0    = hit;
        no_hit_t0 = no_hit;

        #50; 
        hit_t1    = hit;
        no_hit_t1 = no_hit;

        if (hit_t0 !== hit_t1 || no_hit_t0 !== no_hit_t1) begin
            $error("[FAIL] REQ-DEC-005");
            err_cnt++;
        end else begin
            pass_cnt++;
        end
    end
    endtask

    initial begin
        addr_t rand_addr;
        logic  rand_psel;
        int    target_slv;

        $display("START TB_ADDR (N_SLAVES=%0d, ADDR_W=%0d, DATA_W=%0d)", 
                 N_SLAVES, ADDR_WIDTH, DATA_WIDTH);

        S_PADDR = '0;
        S_PSEL  = 1'b0;
        #20;

        check_code(SLV_BASE_ADDR[0], 1'b0, "PSEL_0");

        // Test unmapped below slave 0
        if (SLV_BASE_ADDR[0] > 0) begin
            check_code('0, 1'b1, "UNMAPPED_ZERO");
            check_code(SLV_BASE_ADDR[0] - 1, 1'b1, "UNMAPPED_BELOW_SLV0");
        end

        // Test biên từng slave
        for (int i = 0; i < N_SLAVES; i++) begin
            if (SLV_BASE_ADDR[i] > 0)
            check_code(SLV_BASE_ADDR[i] - 1, 1'b1, $sformatf("SLV%0d_OUT_LOW", i));
            check_code(SLV_BASE_ADDR[i], 1'b1, $sformatf("SLV%0d_BASE_ADDR", i));
            check_code(SLV_BASE_ADDR[i] + SLV_ADDR_SIZE[i] - 1, 1'b1, $sformatf("SLV%0d_END_ADDR", i));
            check_code(SLV_BASE_ADDR[i] + SLV_ADDR_SIZE[i], 1'b1, $sformatf("SLV%0d_OUT_HIGH", i));
        end

        check_combinational_stability();

        // 200 Random tests
        for (int t = 0; t < 200; t++) begin
            rand_psel = ($urandom_range(0, 9) < 8) ? 1'b1 : 1'b0; 
            if (t % 2 == 0) begin
                target_slv = $urandom_range(0, N_SLAVES - 1);
                rand_addr  = SLV_BASE_ADDR[target_slv] + $urandom_range(0, SLV_ADDR_SIZE[target_slv] - 1);
                check_code(rand_addr, rand_psel, $sformatf("RAND_IN_SLV%0d_%0d", target_slv, t));
            end else begin
                rand_addr = {addr_t'(urandom()),addrt'(urandom())};
                check_code(rand_addr, rand_psel, $sformatf("RAND_FULL_%0d", t));
            end
        end

        #20;
        $display("PASS: %0d | ERROR: %0d", pass_cnt, err_cnt);
        if (err_cnt == 0) $display("=== ALL PASSED ===");
        else              $display("=== FAILED ===");
        $finish;
    end
endmodule
