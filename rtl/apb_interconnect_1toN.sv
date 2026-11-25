module apb_interconnect_1toN #(
  parameter int unsigned N_SLAVES    = 4,
  parameter int unsigned ADDR_WIDTH  = 32,
  parameter int unsigned DATA_WIDTH  = 32,
  parameter longint unsigned SLV_BASE_ADDR [N_SLAVES] = '{default: 0},
  parameter longint unsigned SLV_ADDR_SIZE [N_SLAVES] = '{default: 0},
  parameter bit          ERR_ON_UNMAPPED   = 1'b1,
  parameter bit          GATE_UNSELECTED   = 1'b0,
  parameter int unsigned TIMEOUT_CYCLES    = 0,
  parameter bit          CSR_EN            = 1'b1,
  parameter int unsigned TIMEOUT_WIDTH     = 16,
  parameter bit          REG_SLICE         = 1'b0
) (
  input  logic                                     PCLK,
  input  logic                                     PRESETn,
  input  logic                                     warm_rstn_i,

  // S port: nối tới APB master / bridge
  input  logic                                     S_PSEL,
  input  logic                                     S_PENABLE,
  input  logic                                     S_PWRITE,
  input  logic [ADDR_WIDTH-1:0]                    S_PADDR,
  input  logic [DATA_WIDTH-1:0]                    S_PWDATA,
  input  logic [DATA_WIDTH/8-1:0]                  S_PSTRB,     // APB4
  input  logic [2:0]                               S_PPROT,     // APB4
  output logic [DATA_WIDTH-1:0]                    S_PRDATA,
  output logic                                     S_PREADY,
  output logic                                     S_PSLVERR,

  // M ports: nối tới N APB slave
  output logic [N_SLAVES-1:0]                      M_PSEL,
  output logic [N_SLAVES-1:0]                      M_PENABLE,
  output logic [N_SLAVES-1:0]                      M_PWRITE,
  output logic [N_SLAVES-1:0][ADDR_WIDTH-1:0]      M_PADDR,
  output logic [N_SLAVES-1:0][DATA_WIDTH-1:0]      M_PWDATA,
  output logic [N_SLAVES-1:0][DATA_WIDTH/8-1:0]    M_PSTRB,     // APB4
  output logic [N_SLAVES-1:0][2:0]                 M_PPROT,     // APB4
  input  logic [N_SLAVES-1:0][DATA_WIDTH-1:0]      M_PRDATA,
  input  logic [N_SLAVES-1:0]                      M_PREADY,
  input  logic [N_SLAVES-1:0]                      M_PSLVERR,

  // Sideband
  output logic                                     decerr_o,
  output logic                                     timeout_o,

  // CSR interface (CSR_EN=1): nối tới APB CSR block
  input  logic [N_SLAVES-1:0][TIMEOUT_WIDTH-1:0]   csr_timeout_thr_i,
  input  logic [N_SLAVES-1:0]                      csr_eoi_i,
  output logic [N_SLAVES-1:0]                      csr_timeout_pending_o,

  // Interrupt
  output logic                                     irq_o
);

// Internal signals
logic [N_SLAVES-1:0]        hit;
bit                         no_hit;
logic [DATA_WIDTH-1:0]      D_PRDATA;
bit                         D_PREADY;
bit                         D_PSLVERR;
logic [TIMEOUT_WIDTH-1:0]   thr;
bit                         timeout;

//  ADDRESS DECODER

//  REQUEST FAN-OUT

//  DEFAULT SLAVE

//  MUX RESPONSE

//  COUNTER

//  CSR INTERFACE

//  SIDEBAND SIGNAL

endmodule : apb_interconnect_1toN