`timescale 1ns / 10ps
//////////////////////////////////////////////////////////////////////////////////
// Company:     Pinhead Technologies
// Engineer:    Orin Eman
// Copyright (c) 2016 Orin Eman
// 
// Create Date: 07/27/2016 01:06:05 PM
// Design Name: 
// Module Name: registers
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`include "nanoprocessor.vh"

module registers(
    input  [7:0] dataIn, // write data
    input  [3:0] addr,      // register or bit address (from instruction)
    input        clk,
    input  [3:0] ctrl,
    input        execute,
    output [7:0] dataOut,// data from register bank
    output [7:0] a,         // accumulator
    output       e,         // E register
    output       lt,        // a < R0
    output       eq,        // a == R0
    output       z,         // a == 0
    output [3:0] index      // Index for JAI, JAS, LDI and STI
                            // Exposed for strangeness with JAI where R0[3] == 1 turns into JAS
    );

    reg [7:0] registers[15:0];
    reg [7:0] acc;
    reg       ext;

    integer k;
    initial begin
        acc = 0;
        ext = 0;
        for (k = 0; k <= 15; k = k + 1)
            registers[k] = 0;
    end

    // Read registers
    assign a = acc[7:0];
    assign e = ext;
    assign dataOut = (ctrl == `REG_OTA ? a : registers[addr]);
    
    // Tests of accumulator
    wire [8:0] diff;
    assign diff[8:0] = (acc[7:0] - registers[0][7:0]);
    assign eq = (diff[7:0] == 8'b0000_0000); // Or: assign eq = ~|diff[7:0];
    assign lt = diff[8];
    assign z = (acc == 8'b0000_0000);        // Or: assign z = ~|acc[7:0];

    // For JAI, JAS, LDI and STI
    assign index = addr[3:0]|registers[0][3:0];
   
    // Register operations 
    always @(posedge clk)
    begin
        if (execute)
        begin
            case ( ctrl )
                `REG_NOP:
                    ;
                `REG_STR:
                    registers[addr] <= dataIn;
                `REG_LDR:
                    acc[7:0] <= dataIn;
                `REG_STA:
                    registers[addr] <= acc[7:0];
                `REG_LDA:
                    acc[7:0] <= registers[addr];
                `REG_CBN:
                    acc[addr[2:0]] <= 1'b0;
                `REG_SBN:
                    acc[addr[2:0]] <= 1'b1;
                `REG_ALU:
                begin
                    case ( addr[2:0] )
                        3'b000: // INB
                             {ext,acc[7:0]} <= acc[7:0] + 1;
                        3'b001: // DEB
                            {ext,acc[7:0]} <= acc[7:0] - 1;
                        3'b010: // IND - increment BCD
                        begin
                            if (acc[3:0] != 4'b1001)
                            begin
                                acc[3:0] <= acc[3:0] + 1;
                                ext <= 1'b0;
                            end
                            else begin
                                acc[3:0] <= 4'b0000;
                                if (acc[7:4] != 4'b1001 )
                                begin
                                    acc[7:4] <= acc[7:4] + 1;
                                    ext <= 1'b0;
                                end
                                else begin
                                    acc[7:4] <= 4'b0000;
                                    ext <= 1'b1;
                                end
                            end
                        end
                        3'b011: // DED - decrement BCD
                        begin
                            if (acc[3:0] != 4'b0000)
                            begin
                                acc[3:0] <= acc[3:0] - 1;
                                ext <= 1'b0;
                            end
                            else begin
                                acc[3:0] <= 4'b1001;
                                if (acc[7:4] != 4'b0000 )
                                begin
                                    acc[7:4] <= acc[7:4] - 1;
                                    ext <= 1'b0;
                                end
                                else begin
                                    acc[7:4] <= 4'b1001;
                                    ext <= 1'b1;
                                end
                            end
                        end
                        3'b100: // CLA
                            acc[7:0] <= 8'b0000_0000;
                        3'b101: // CMA
                            acc[7:0] <= ~acc[7:0];
                        3'b110: // RSA
                            acc[7:0] <= {1'b0, acc[7:1]};
                        3'b111: // LSA
                            acc[7:0] <= {acc[6:0], 1'b0};
                    endcase
                end
                `REG_STE:
                    ext <= 1'b1;
                `REG_CLE:
                    ext <= 1'b0;
                `REG_LDI:
                    acc[7:0] <= registers[index];   // Load Indexed
                `REG_STI:
                    registers[index] <= acc[7:0];   // Store Indexed
                // OTA
                `REG_OTA:
                    ;   // Do nothing, but acc is gated to regDataOut
                // Unused
                `REG_00D, `REG_00E, `REG_00F:
                    ;

                default:
                    ;

            endcase
        end
    end
endmodule
