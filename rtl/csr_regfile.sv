/* Copyright (c) 2024-2026 Maveric NU. All rights reserved. */

//-------------------------------
// Engineer     : Yesmurat
// Create Date  : 02/06/2026
// Last Revision: 02/06/2026
//------------------------------

// -----------------------------------------------------------------------
// This is a Zicsr CSR register file component of processor based on RISC-V architecture.
// -----------------------------------------------------------------------

/*
Implemented CSRs
Machine Information (read-only)
  0xF11  mvendorid   Non-commercial → 0
  0xF12  marchid     Unregistered   → 0
  0xF13  mimpid      Implementation revision → 1
  0xF14  mhartid     Single hart    → 0
  0x301  misa        RV64IM         → see MISA_VAL

Machine Status (partially writable)
  0x300  mstatus     MPP hardwired 11 (M-mode only); all other
                     fields WARL → 0 until trap support is added
Scratch (fully writable)
  0x340  mscratch    General-purpose M-mode scratch register
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

    // Write logic (synchronous).
    always_ff @(posedge clk_i, posedge arst_i) begin

        if (arst_i) begin

            mstatus_r  <= MSTATUS_RESET;
            mscratch_r <= '0;

        end
        
        else if (we_i) begin

            case (waddr_i)

                // mstatus: accept writes but keep MPP fixed at 11 (WARL).
                12'h300: mstatus_r  <= (wdata_i & ~(64'd3 << 11)) | MSTATUS_RESET;
                12'h340: mscratch_r <= wdata_i;
                default: ; // all other writes silently ignored

            endcase

        end

    end

    // Read logic (combinational).
    always_comb begin

        case (raddr_i)
        
            // Machine status.
            12'h300: rdata_o = mstatus_r;

            // Machine ISA and identification.
            12'h301: rdata_o = MISA_VAL;
            12'hF11: rdata_o = '0;                    // mvendorid
            12'hF12: rdata_o = '0;                    // marchid
            12'hF13: rdata_o = 64'd1;                 // mimpid
            12'hF14: rdata_o = '0;                    // mhartid

            // Scratch.
            12'h340: rdata_o = mscratch_r;

            default: rdata_o = '0;

        endcase

    end

endmodule
