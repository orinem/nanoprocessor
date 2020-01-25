`timescale 1ns / 10ps
//////////////////////////////////////////////////////////////////////////////////
// Company:     Pinhead Technologies
// Engineer:    Orin Eman
// Copyright (c) 2016 Orin Eman
//
// Create Date: 07/27/2016 04:09:38 PM
// Design Name: 
// Module Name: output_bit
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


module output_bit(
    input in,
    output out,
    input enable
    );
    //assign out = (in | !enable) ? 1'bZ : 1'b0;
    assign out = enable ? in : 1'bZ;
endmodule
