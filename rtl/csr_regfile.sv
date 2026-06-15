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

    // misa: MXL=2 (RV64) at bits [63:62], extensions I (bit 8) + M (bit 12).
    localparam logic [DATA_WIDTH-1:0] MISA_VAL =
        (2 << 62) | (1 << 8) | (1 << 12);  // RV64IM

    // mstatus: MPP = 2'b11 (M-mode only), all other fields 0.
    localparam logic [DATA_WIDTH-1:0] MSTATUS_RESET =
        (64'd3 << 11);  // MPP[12:11] = 11

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

                12'h305: mtvec_r    <= wdata_i;

                // mstatus: accept writes but keep MPP fixed at 11 (WARL).
                12'h300: mstatus_r  <= (wdata_i & ~(64'd3 << 11)) | MSTATUS_RESET;

                12'h340: mscratch_r <= wdata_i;
                12'h341: mepc_r     <= wdata_i;
                12'h342: mcause_r   <= wdata_i;
                default: ; // all other writes silently ignored

            endcase

        end

    end

    // Read logic (combinational).
    always_comb begin

        case (raddr_i)
    
            // Machine Information Registers
            12'hF11: rdata_o = '0;                    // mvendorid
            12'hF12: rdata_o = '0;                    // marchid
            12'hF13: rdata_o = 64'd1;                 // mimpid
            12'hF14: rdata_o = '0;                    // mhartid

            // Machine Trap Setup
            12'h300: rdata_o = mstatus_r;             // mstatus
            12'h301: rdata_o = MISA_VAL;              // misa
            12'h305: rdata_o = mtvec_r;               // mtvec

            // Machine Trap Handling
            12'h340: rdata_o = mscratch_r;            // mscratch
            12'h341: rdata_o = mepc_r;                // mepc
            12'h342: rdata_o = mcause_r;              // mcause

            default: rdata_o = '0;

        endcase

    end

    assign mtvec_o = {mtvec_r[DATA_WIDTH-1:2], 2'b00};
    assign mepc_o  = mepc_r;

endmodule
