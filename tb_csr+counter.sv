`timescale 1ns / 1ps

module tb_timeout_counter;

    parameter int unsigned N_SLAVES       = 4;
    parameter int unsigned TIMEOUT_WIDTH  = 16;
    parameter int unsigned TIMEOUT_CYCLES = 8;    
    parameter bit          CSR_EN         = 1'b1;

    localparam time CLK_PERIOD = 10ns;

    logic PCLK;
    logic PRESETn;
    logic warm_rstn_i;

    logic [N_SLAVES-1:0] M_PSEL;
    logic M_PENABLE;
    logic M_PREADY;

    logic [N_SLAVES-1:0][TIMEOUT_WIDTH-1:0]csr_timeout_thr_i;
    logic [N_SLAVES-1:0]csr_eoi_i;

    logic  timeout_o;
    logic [N_SLAVES-1:0]csr_timeout_pending_o;
    logic irq_o;

    int pass_count = 0;
    int fail_count = 0;


    timeout_counter #(
        .N_SLAVES       (N_SLAVES),
        .TIMEOUT_WIDTH  (TIMEOUT_WIDTH),
        .TIMEOUT_CYCLES (TIMEOUT_CYCLES),
        .CSR_EN         (CSR_EN)
    ) dut (
        .PCLK                  (PCLK),
        .PRESETn               (PRESETn),
        .warm_rstn_i           (warm_rstn_i),
        .M_PSEL                (M_PSEL),
        .M_PENABLE             (M_PENABLE),
        .M_PREADY              (M_PREADY),
        .csr_timeout_thr_i     (csr_timeout_thr_i),
        .csr_eoi_i             (csr_eoi_i),
        .timeout_o             (timeout_o),
        .csr_timeout_pending_o (csr_timeout_pending_o),
        .irq_o                 (irq_o)
    );

    initial begin
        PCLK = 1'b0;
        forever #(CLK_PERIOD / 2) PCLK = ~PCLK;
    end

    // REQ-VER-019: 
    always @(posedge PCLK) begin
        if (PRESETn) begin
            #1;
            if (irq_o !== (|csr_timeout_pending_o)) begin
                $error("[FAIL] REQ-VER-019 | irq_o (%b) != |csr_timeout_pending_o (%b)",
                       irq_o, csr_timeout_pending_o);
                fail_count++;
            end
        end
    end


    // reset ban dau
    task automatic apply_cold_reset();
        begin
            PRESETn           <= 1'b0;
            warm_rstn_i       <= 1'b1;
            M_PSEL            <= '0;
            M_PENABLE         <= 1'b0;
            M_PREADY          <= 1'b0;
            csr_eoi_i         <= '0;
            for (int i = 0; i < N_SLAVES; i++) begin
                csr_timeout_thr_i[i] <= 16'd5;
            end
            repeat (3) @(posedge PCLK);
            PRESETn <= 1'b1;
            @(posedge PCLK);
        end
    endtask

    task automatic check (
        input int                  slave_idx,
        input int                  wait_states,      
        input logic [TIMEOUT_WIDTH-1:0] new_thr_mid_xfer, // REQ-CSR-006
        input bit                  change_thr_mid,   // REQ-CSR-006
        input bit                  exp_timeout,      
        input string               case_id
    );
        bit got_timeout;
        int actual_cycles;
        begin
            got_timeout   = 1'b0;
            actual_cycles = 0;

            @(posedge PCLK);
            M_PSEL            <= '0;
            M_PSEL[slave_idx] <= 1'b1;
            M_PENABLE         <= 1'b0;
            M_PREADY          <= 1'b0;

            @(posedge PCLK);
            M_PENABLE <= 1'b1;

            // count wait_states
            for (int w = 0; w < wait_states; w++) begin
                // test REQ-CSR-006
                if (change_thr_mid && w == 1) begin
                    csr_timeout_thr_i[slave_idx] <= new_thr_mid_xfer;
                end

                @(posedge PCLK);
                actual_cycles++;
                #1; 
                if (timeout_o === 1'b1) begin
                    got_timeout = 1'b1;
                    break;
                end
            end

            if (!got_timeout) begin
                M_PREADY <= 1'b1;
                @(posedge PCLK);
                actual_cycles++;
                #1;
                if (timeout_o === 1'b1) begin
                    got_timeout = 1'b1;
                end
            end

            // IDLE
            M_PSEL    <= '0;
            M_PENABLE <= 1'b0;
            M_PREADY  <= 1'b0;

            if (got_timeout !== exp_timeout) begin
                $error("[FAIL] %s | Slave=%0d | Wait=%0d | Got timeout=%b (at cycle %0d) | Expected=%b",
                       case_id, slave_idx, wait_states, got_timeout, actual_cycles, exp_timeout);
                fail_count++;
            end else begin
                $display("[PASS] %s | Slave=%0d | Wait=%0d | timeout=%b | pending=%b",
                         case_id, slave_idx, wait_states, got_timeout, csr_timeout_pending_o);
                pass_count++;
            end
        end
    endtask

    // REQ-VER-017
    task automatic check_warm_rst (
        input int    slave_idx,
        input int    wait_before_rst,
        input int    rst_duration_cycles,
        input string case_id
    );
        logic [N_SLAVES-1:0] pending_before;
        bit spurious_timeout;
        begin
            spurious_timeout = 1'b0;
            pending_before   = csr_timeout_pending_o;

            @(posedge PCLK);
            M_PSEL            <= '0;
            M_PSEL[slave_idx] <= 1'b1;
            M_PENABLE         <= 1'b0;
            M_PREADY          <= 1'b0;

            @(posedge PCLK);
            M_PENABLE <= 1'b1;

            repeat (wait_before_rst) @(posedge PCLK);

            warm_rstn_i <= 1'b0;
            repeat (rst_duration_cycles) begin
                @(posedge PCLK);
                #1;
                if (timeout_o === 1'b1) spurious_timeout = 1'b1;
            end

            warm_rstn_i <= 1'b1;
            M_PSEL      <= '0;
            M_PENABLE   <= 1'b0;
            @(posedge PCLK);
            #1;

            if (spurious_timeout || (csr_timeout_pending_o !== pending_before)) begin
                $error("[FAIL] %s | Spurious timeout=%b | Pending before=%b, after=%b",
                       case_id, spurious_timeout, pending_before, csr_timeout_pending_o);
                fail_count++;
            end else begin
                $display("[PASS] %s | Counter reset cleanly, pending preserved (%b)",
                         case_id, csr_timeout_pending_o);
                pass_count++;
            end
        end
    endtask

    initial begin
        apply_cold_reset();

        // GROUP 1: REQ-VER-016 
        csr_timeout_thr_i[0] <= 16'd4; 
        csr_timeout_thr_i[1] <= 16'd0; 
        csr_timeout_thr_i[2] <= 16'd6;
        @(posedge PCLK);

        check(0, 4, 0, 0, 1'b0, "REQ-VER-016_Exact_T_Wait");

        check(0, 5, 0, 0, 1'b1, "REQ-VER-016_T_Plus_1_Timeout");

        check(1, 20, 0, 0, 1'b0, "REQ-VER-016_T_Zero_No_Timeout");

        
        // GROUP 2: REQ-CSR-006 
        check(2, 4, 16'd2, 1'b1, 1'b0, "REQ-CSR-006_Mid_Xfer_Keep_Old_Thr");
        check(2, 3, 16'd2, 1'b0, 1'b1, "REQ-CSR-006_Next_Xfer_Use_New_Thr");

        // GROUP 3: REQ-VER-017 
        csr_timeout_thr_i[3] <= 16'd5;
        @(posedge PCLK);
        check_warm_rst(3, 3, 1, "REQ-VER-017_WarmRst_1Cycle_Mid_Wait");

        check(3, 4, 0, 0, 1'b0, "REQ-VER-017_Counter_Cleared_After_WarmRst");

        // REQ-VER-018 
        @(posedge PCLK);
        csr_eoi_i <= 4'b0001;
        @(posedge PCLK);
        csr_eoi_i <= 4'b0000;
        @(posedge PCLK);
        #1;
        if (csr_timeout_pending_o !== 4'b0100) begin
            $error("[FAIL] REQ-VER-018_EOI_Clear_Slave0 | Got pending=%b, Expected=0100", csr_timeout_pending_o);
            fail_count++;
        end else begin
            $display("[PASS] REQ-VER-018_EOI_Clear_Slave0 | Pending=%b", csr_timeout_pending_o);
            pass_count++;
        end

        csr_timeout_thr_i[1] <= 16'd2;
        @(posedge PCLK);
        M_PSEL    <= 4'b0010; 
        M_PENABLE <= 1'b0;
        M_PREADY  <= 1'b0;
        @(posedge PCLK);
        M_PENABLE <= 1'b1;    
        @(posedge PCLK);      
        @(posedge PCLK);      
        csr_eoi_i <= 4'b0100; 
        @(posedge PCLK);
        csr_eoi_i <= 4'b0000;
        M_PSEL    <= '0;
        M_PENABLE <= 1'b0;
        @(posedge PCLK);
        #1;
        if (csr_timeout_pending_o !== 4'b0010) begin
            $error("[FAIL] REQ-VER-018_Simultaneous_Timeout_And_EOI | Got pending=%b, Expected=0010",
                   csr_timeout_pending_o);
            fail_count++;
        end else begin
            $display("[PASS] REQ-VER-018_Simultaneous_Timeout_And_EOI | Pending=%b", csr_timeout_pending_o);
            pass_count++;
        end
        
        //  REQ-CSR-012 
        csr_timeout_thr_i[2] <= 16'd2;
        check(2, 3, 0, 0, 1'b1, "REQ-CSR-012_Setup_Slave2_Pending");

        @(posedge PCLK);
        M_PSEL    <= 4'b0100; 
        M_PENABLE <= 1'b0;
        M_PREADY  <= 1'b0;

        @(posedge PCLK);
        M_PENABLE <= 1'b1;    
        @(posedge PCLK);      
        @(posedge PCLK);      
        csr_eoi_i <= 4'b0100; 

        @(posedge PCLK);
        csr_eoi_i <= 4'b0000; 
        M_PSEL    <= '0;      
        M_PENABLE <= 1'b0;
        @(posedge PCLK);
        #1;

        if (csr_timeout_pending_o[2] !== 1'b1) begin
            $error("[FAIL] REQ-CSR-012_Same_Slave_Set_Wins_EOI | Got pending[2]=%b, Expected=1 (Event lost!)",
                   csr_timeout_pending_o[2]);
            fail_count++;
        end else begin
            $display("[PASS] REQ-CSR-012_Same_Slave_Set_Wins_EOI | pending=%b (Set won over EOI)",
                     csr_timeout_pending_o);
            pass_count++;
        end
        
        if (fail_count == 0) $display("ALL TESTS PASSED!");
        else $display("SOME TESTS FAILED! CHECK ERRORS ABOVE.");
        
        $finish;
    end

endmodule