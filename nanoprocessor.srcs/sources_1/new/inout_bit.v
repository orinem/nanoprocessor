`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:     Pinhead Technologies
// Engineer:    Orin Eman
// Copyright (c) 2016 Orin Eman
// 
// Create Date: 07/27/2016 04:41:21 PM
// Design Name: 
// Module Name: inout_bit
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


module inout_bit(
    input in,
    output out
    );
    
    assign out = in ? 1'bZ : 0;
endmodule
