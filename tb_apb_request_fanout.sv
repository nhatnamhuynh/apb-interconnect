`timescale 1ns/1ps

module tb_apb_request_fanout;

    parameter int unsigned ADDR_WIDTH      = 32;
    parameter int unsigned DATA_WIDTH      = 32;
    parameter bit          GATE_UNSELECTED = 1'b1;
    parameter int unsigned N_SLAVES        = 4;

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam time         CLK_PERIOD = 10ns;

    logic                              PCLK;
    logic                              PRESETn;
    logic                              warm_rstn_i;

    logic [N_SLAVES-1:0]               hit_i;
    logic                              S_PSEL;
    logic                              S_PENABLE;
    logic                              S_PWRITE;
    logic [ADDR_WIDTH-1:0]             S_PADDR;
    logic [DATA_WIDTH-1:0]             S_PWDATA;
    logic [STRB_WIDTH-1:0]             S_PSTRB;
    logic [2:0]                        S_PPROT;

    logic [N_SLAVES-1:0]               M_PSEL;
    logic [N_SLAVES-1:0]               M_PENABLE;
    logic [N_SLAVES-1:0]               M_PWRITE;
    logic [N_SLAVES-1:0][ADDR_WIDTH-1:0] M_PADDR;
    logic [N_SLAVES-1:0][DATA_WIDTH-1:0] M_PWDATA;
    logic [N_SLAVES-1:0][STRB_WIDTH-1:0] M_PSTRB;
    logic [N_SLAVES-1:0][2:0]            M_PPROT;

    int pass_count = 0;
    int fail_count = 0;

    apb_request_fanout #(
        .N_SLAVES        (N_SLAVES),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .GATE_UNSELECTED (GATE_UNSELECTED)
    ) dut (
        .PCLK        (PCLK),
        .PRESETn     (PRESETn),
        .warm_rstn_i (warm_rstn_i),
        .hit_i       (hit_i),
        .S_PSEL      (S_PSEL),
        .S_PENABLE   (S_PENABLE),
        .S_PWRITE    (S_PWRITE),
        .S_PADDR     (S_PADDR),
        .S_PWDATA    (S_PWDATA),
        .S_PSTRB     (S_PSTRB),
        .S_PPROT     (S_PPROT),
        .M_PSEL      (M_PSEL),
        .M_PENABLE   (M_PENABLE),
        .M_PWRITE    (M_PWRITE),
        .M_PADDR     (M_PADDR),
        .M_PWDATA    (M_PWDATA),
        .M_PSTRB     (M_PSTRB),
        .M_PPROT     (M_PPROT)
    );

    initial begin
        PCLK = 1'b0;
        forever #(CLK_PERIOD / 2) PCLK = ~PCLK;
    end

    genvar g;
    generate
        for (g = 0; g < N_SLAVES; g++) begin : gen_apb_assert
            property p_penable_requires_psel;
                @(posedge PCLK) disable iff (!PRESETn)
                M_PENABLE[g] |-> M_PSEL[g];
            endproperty
            assert_penable_psel: assert property (p_penable_requires_psel)
                else begin
                    $error("[FAIL] REQ-APB-001 | Slave %0d: M_PENABLE=1 while M_PSEL=0!", g);
                    fail_count++;
                end

            property p_no_aborted_setup_phase;
                @(posedge PCLK) disable iff (!PRESETn)
                (M_PSEL[g] && !M_PENABLE[g]) |=> (M_PSEL[g] && M_PENABLE[g]);
            endproperty
            assert_req_wrm_006: assert property (p_no_aborted_setup_phase)
                else begin
                    $error("[FAIL] REQ-WRM-006 | Slave %0d: Aborted SETUP phase without ACCESS phase!", g);
                    fail_count++;
                end
        end
    endgenerate

    task automatic apply_cold_reset();
        begin
            PRESETn     <= 1'b0;
            warm_rstn_i <= 1'b1;
            hit_i       <= '0;
            S_PSEL      <= 1'b0;
            S_PENABLE   <= 1'b0;
            S_PWRITE    <= 1'b0;
            S_PADDR     <= '0;
            S_PWDATA    <= '0;
            S_PSTRB     <= '0;
            S_PPROT     <= '0;
            repeat (3) @(posedge PCLK);
            PRESETn     <= 1'b1;
            @(posedge PCLK);
        end
    endtask

    task automatic verify_routing(
        input int                  exp_sel_idx, 
        input logic [ADDR_WIDTH-1:0] exp_addr,
        input logic [DATA_WIDTH-1:0] exp_wdata,
        input logic                  exp_write,
        input logic [STRB_WIDTH-1:0] exp_strb,
        input logic [2:0]            exp_prot,
        input logic                  exp_penable,
        input string                 case_id
    );
        bit err;
        begin
            err = 1'b0;
            for (int i = 0; i < N_SLAVES; i++) begin
                if (i == exp_sel_idx) begin
                    if (M_PSEL[i]    !== 1'b1 ||
                        M_PENABLE[i] !== exp_penable ||
                        M_PADDR[i]   !== exp_addr ||
                        M_PWDATA[i]  !== exp_wdata ||
                        M_PWRITE[i]  !== exp_write ||
                        M_PSTRB[i]   !== exp_strb ||
                        M_PPROT[i]   !== exp_prot) begin
                        $error("[FAIL] %s | Selected Slave %0d mismatch! PSEL=%b, PENABLE=%b, PADDR=%h (exp %h), PWDATA=%h (exp %h)",
                               case_id, i, M_PSEL[i], M_PENABLE[i], M_PADDR[i], exp_addr, M_PWDATA[i], exp_wdata);
                        err = 1'b1;
                    end
                end else begin
                    if (M_PSEL[i] !== 1'b0) begin
                        $error("[FAIL] %s | Unselected Slave %0d has M_PSEL=1!", case_id, i);
                        err = 1'b1;
                    end
                    if (GATE_UNSELECTED) begin
                        if (M_PENABLE[i] !== 1'b0 || M_PWRITE[i] !== 1'b0 ||
                            M_PADDR[i]   !== '0   || M_PWDATA[i] !== '0   ||
                            M_PSTRB[i]   !== '0   || M_PPROT[i]  !== '0) begin
                            $error("[FAIL] %s | Unselected Slave %0d not gated to 0 when GATE_UNSELECTED=1!", case_id, i);
                            err = 1'b1;
                        end
                    end else begin
                        if (M_PENABLE[i] !== 1'b0     || M_PADDR[i] !== exp_addr  ||
                            M_PWDATA[i]  !== exp_wdata || M_PWRITE[i] !== exp_write ||
                            M_PSTRB[i]   !== exp_strb  || M_PPROT[i] !== exp_prot) begin
                            $error("[FAIL] %s | Unselected Slave %0d not receiving broadcast when GATE_UNSELECTED=0!", case_id, i);
                            err = 1'b1;
                        end
                    end
                end
            end

            if (err) fail_count++;
            else     pass_count++;
        end
    endtask

    task automatic run_single_transfer(
        input int                  slave_idx,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] wdata,
        input logic                  pwrite,
        input logic [STRB_WIDTH-1:0] pstrb,
        input logic [2:0]            pprot,
        input int                  wait_states,
        input bit                  go_idle_after,
        input string                 case_id
    );
        begin
            S_PSEL    <= 1'b1;
            S_PENABLE <= 1'b0;
            S_PWRITE  <= pwrite;
            S_PADDR   <= addr;
            S_PWDATA  <= wdata;
            S_PSTRB   <= pstrb;
            S_PPROT   <= pprot;
            hit_i     <= (slave_idx >= 0) ? (1'b1 << slave_idx) : '0;

            @(posedge PCLK);
            #1;
            verify_routing(slave_idx, addr, wdata, pwrite, pstrb, pprot, 1'b0, {case_id, "_SETUP"});

            S_PENABLE <= 1'b1;
            repeat (wait_states + 1) begin
                @(posedge PCLK);
                #1;
                verify_routing(slave_idx, addr, wdata, pwrite, pstrb, pprot, 1'b1, {case_id, "_ACCESS"});
            end

            if (go_idle_after) begin
                S_PSEL    <= 1'b0;
                S_PENABLE <= 1'b0;
                hit_i     <= '0;
                @(posedge PCLK);
                #1;
                verify_routing(-1, '0, '0, 1'b0, '0, '0, 1'b0, {case_id, "_IDLE"});
            end
        end
    endtask

    initial begin
        apply_cold_reset();

        run_single_transfer(
            .slave_idx(0), .addr(32'h1000_0003), .wdata(32'hDEAD_BEEF),
            .pwrite(1'b1), .pstrb(4'b1100), .pprot(3'b010),
            .wait_states(0), .go_idle_after(1'b1),
            .case_id("CASE1_Mapped_Write_Unaligned")
        );

        run_single_transfer(
            .slave_idx(-1), .addr(32'hFFFF_0000), .wdata(32'h1234_5678),
            .pwrite(1'b1), .pstrb(4'b1111), .pprot(3'b000),
            .wait_states(0), .go_idle_after(1'b1),
            .case_id("CASE2_Unmapped_No_Hit")
        );

        run_single_transfer(
            .slave_idx(2), .addr(32'h3000_0010), .wdata(32'hCAFE_BABE),
            .pwrite(1'b0), .pstrb(4'b0000), .pprot(3'b001),
            .wait_states(5), .go_idle_after(1'b1),
            .case_id("CASE3_Wait_States_Stability")
        );

        run_single_transfer(
            .slave_idx(1), .addr(32'h2000_0004), .wdata(32'h1111_2222),
            .pwrite(1'b1), .pstrb(4'b1111), .pprot(3'b000),
            .wait_states(0), .go_idle_after(1'b0),
            .case_id("CASE4_B2B_Xfer1_Slave1")
        );
        run_single_transfer(
            .slave_idx(3), .addr(32'h4000_0008), .wdata(32'h3333_4444),
            .pwrite(1'b0), .pstrb(4'b0000), .pprot(3'b100),
            .wait_states(1), .go_idle_after(1'b1),
            .case_id("CASE4_B2B_Xfer2_Slave3")
        );

        S_PSEL    <= 1'b1;
        S_PENABLE <= 1'b0;
        S_PADDR   <= 32'h1000_0020;
        S_PWDATA  <= 32'hAAAA_5555;
        S_PWRITE  <= 1'b1;
        S_PSTRB   <= 4'b1111;
        S_PPROT   <= 3'b000;
        hit_i     <= 4'b0001;

        @(posedge PCLK);
        S_PENABLE <= 1'b1;
        @(posedge PCLK);

        warm_rstn_i <= 1'b0;
        @(posedge PCLK);
        #1;
        verify_routing(-1, '0, '0, 1'b0, '0, '0, 1'b0, "CASE5_WarmRst_Asserted_In_Access");

        warm_rstn_i <= 1'b1;
        @(posedge PCLK);
        #1;
        verify_routing(-1, '0, '0, 1'b0, '0, '0, 1'b0, "CASE5_WarmRst_Deasserted_Still_Masked");

        S_PSEL    <= 1'b0;
        S_PENABLE <= 1'b0;
        hit_i     <= '0;
        @(posedge PCLK);

        run_single_transfer(
            .slave_idx(0), .addr(32'h1000_0024), .wdata(32'h5555_AAAA),
            .pwrite(1'b1), .pstrb(4'b1111), .pprot(3'b000),
            .wait_states(0), .go_idle_after(1'b1),
            .case_id("CASE5_New_Xfer_After_WarmRst")
        );

        S_PSEL      <= 1'b1;
        S_PENABLE   <= 1'b0;
        S_PADDR     <= 32'h2000_0030;
        hit_i       <= 4'b0010;
        warm_rstn_i <= 1'b0;
        @(posedge PCLK);
        #1;
        verify_routing(-1, '0, '0, 1'b0, '0, '0, 1'b0, "CASE6_WarmRst_At_Setup_Masked");

        warm_rstn_i <= 1'b1;
        S_PENABLE   <= 1'b1;
        @(posedge PCLK);
        #1;
        verify_routing(-1, '0, '0, 1'b0, '0, '0, 1'b0, "CASE6_WarmRst_At_Setup_Hold_Mask");

        S_PSEL    <= 1'b0;
        S_PENABLE <= 1'b0;
        hit_i     <= '0;
        @(posedge PCLK);

        if (fail_count == 0) $display("RESULT: ALL TESTS PASSED!");
        else                 $display("RESULT: SOME TESTS FAILED!");
        $finish;
    end

endmodule
