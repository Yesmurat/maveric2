/* Copyright (c) 2024-2026 Texer.AI. All rights reserved. */

//-------------------------------
// Engineer     : Yesmurat
// Create Date  : 02/06/2026
// Last Revision: 02/06/2026
//------------------------------

// -----------------------------------------------------------------------
// This is a register file that holds Control and Status Registers.
// -----------------------------------------------------------------------

/* Implemented CSRs

Machine Information Registers (read-only)
    0xF11  mvendorid   Non-commercial -> 0
    0xF12  marchid     Unregistered   -> 0
    0xF13  mimpid      Implementation -> 1
    0xF14  mhartid     Single hart    -> 0

Machine Trap Setup (read/write)
    0x300  mstatus     MPP hardwired 11 (M-mode only)
    0x301  misa        RV64IM         -> see MISA_VAL
    0x305: mtvec       Machine trap-handler base address.

Machine Trap Handling (read/write)
    0x340  mscratch    Machine scratch register
    0x341  mepc        Machine exception program counter
    0x342  mcause      Machine trap cause
*/

module csr_regfile
// Parameters
#(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 12
)
// Port declaration.
(
    // Common clock & reset signal.
    input  logic                   clk_i,
    input  logic                   arst_i,

    // Read port (combinational).
    input  logic [ADDR_WIDTH - 1:0] raddr_i,
    output logic [DATA_WIDTH - 1:0] rdata_o,

    // Write port (synchronous, qualified by we_i).
    input  logic [ADDR_WIDTH - 1:0] waddr_i,
    input  logic [DATA_WIDTH - 1:0] wdata_i,
    input  logic                    we_i,

    // Trap handling.
    input  logic                     trap_i,
    input  logic [DATA_WIDTH - 1:0]  trap_pc_i,     // saved to mepc
    input  logic [DATA_WIDTH - 1:0]  trap_cause_i, // saved to mcause
    input  logic                     mret_instr_i,

    output logic [DATA_WIDTH - 1:0]  mtvec_o,
    output logic [DATA_WIDTH - 1:0]  mepc_o

);

    localparam logic [11:0] CSR_MVENDORID = 12'hF11,
                            CSR_MARCHID   = 12'hF12,
                            CSR_MIMPID    = 12'hF13,
                            CSR_MHARTID   = 12'hF14,
                            CSR_MSTATUS   = 12'h300,
                            CSR_MISA      = 12'h301,
                            CSR_MTVEC     = 12'h305,
                            CSR_MSCRATCH  = 12'h340,
                            CSR_MEPC      = 12'h341,
                            CSR_MCAUSE    = 12'h342;

    // MXL=2 (RV64) at bits[63:62], I at bit 8, M at bit 12
    localparam logic [DATA_WIDTH-1:0] MISA_VAL     = 64'h8000_0000_0000_1100;

    // MPP[12:11] = 2'b11 (M-mode)
    localparam logic [DATA_WIDTH-1:0] MSTATUS_RESET = 64'h0000_0000_0000_1800;

    // Writable registers.
    logic [DATA_WIDTH - 1:0] mstatus_r;
    logic [DATA_WIDTH - 1:0] mscratch_r;
    logic [DATA_WIDTH - 1:0] mtvec_r;
    logic [DATA_WIDTH - 1:0] mepc_r;
    logic [DATA_WIDTH - 1:0] mcause_r;

    // Write logic (synchronous).
    always_ff @(posedge clk_i, posedge arst_i) begin

        if (arst_i) begin

            mstatus_r  <= MSTATUS_RESET;
            mscratch_r <= '0;
            mtvec_r    <= '0;
            mepc_r     <= '0;
            mcause_r   <= '0;

        end

        else if (trap_i) begin

            mepc_r           <= trap_pc_i;
            mcause_r         <= trap_cause_i;
            mstatus_r[7]     <= mstatus_r[3];
            mstatus_r[3]     <= 1'b0;
            mstatus_r[12:11] <= 2'b11;
            // MIE is mstatus[3];
            // MPIE is mstatus[7];
            // MPP is mstatus[12:11];
            
        end

        else if (mret_instr_i) begin

            mstatus_r[3]     <= mstatus_r[7];
            mstatus_r[7]     <= 1'b1;
            mstatus_r[12:11] <= 2'b11;

        end
        
        else if (we_i) begin

            case (waddr_i)

                CSR_MTVEC    : mtvec_r    <= wdata_i;
                CSR_MSTATUS  : mstatus_r  <= (wdata_i & ~(64'd3 << 11)) | MSTATUS_RESET;
                CSR_MSCRATCH : mscratch_r <= wdata_i;
                CSR_MEPC     : mepc_r     <= wdata_i;
                CSR_MCAUSE   : mcause_r   <= wdata_i;
                default: ; // all other writes silently ignored

            endcase

        end

    end

    // Read logic (combinational).
    always_comb begin

        case (raddr_i)
    
            // Machine Information Registers
            CSR_MVENDORID : rdata_o = '0;                    // mvendorid
            CSR_MARCHID   : rdata_o = '0;                    // marchid
            CSR_MIMPID    : rdata_o = 64'd1;                 // mimpid
            CSR_MHARTID   : rdata_o = '0;                    // mhartid

            // Machine Trap Setup
            CSR_MSTATUS   : rdata_o = mstatus_r;             // mstatus
            CSR_MISA      : rdata_o = MISA_VAL;              // misa
            CSR_MTVEC     : rdata_o = mtvec_r;               // mtvec

            // Machine Trap Handling
            CSR_MSCRATCH  : rdata_o = mscratch_r;            // mscratch
            CSR_MEPC      : rdata_o = mepc_r;                // mepc
            CSR_MCAUSE    : rdata_o = mcause_r;              // mcause

            default: rdata_o = '0;

        endcase

    end

    assign mtvec_o = {mtvec_r[DATA_WIDTH-1:2], 2'b00};
    assign mepc_o  = mepc_r;

endmodule
