/* Copyright (c) 2024-2026 Maveric NU. All rights reserved. */

//-------------------------------
// Engineer     : Yesmurat Sagyndyk
// Create Date  : 20/01/2025
// Last Revision: 05/06/2026
//------------------------------

// ------------------------------------------------------
// This is a 4-to-1 mux module.
// ------------------------------------------------------

module mux4to1
// Parameters.
#(
    parameter DATA_WIDTH = 64
)
// Port decleration.
(
    // Input interface.
    input logic [1:0] control_signal_i,
    input logic [DATA_WIDTH-1:0] mux_0_i,
    input logic [DATA_WIDTH-1:0] mux_1_i,
    input logic [DATA_WIDTH-1:0] mux_2_i,
    input logic [DATA_WIDTH-1:0] mux_3_i,

    // Output interface.
    output logic [DATA_WIDTH-1:0] mux_o
);

    // MUX logic.
    always_comb begin
        case (control_signal_i)
            2'd0: mux_o = mux_0_i;
            2'd1: mux_o = mux_1_i;
            2'd2: mux_o = mux_2_i;
            2'd3: mux_o = mux_3_i;
        endcase
    end

endmodule
