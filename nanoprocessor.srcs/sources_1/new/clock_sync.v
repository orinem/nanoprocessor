`timescale 1ns / 10ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/27/2016 03:39:38 PM
// Design Name: 
// Module Name: clock_sync
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


module clock_sync
(
    input   clk,
            di,
    output  do
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] ss = 2'b00;

    assign do = ss[1];

    always @(posedge clk) begin
        ss[0] <= di;
        ss[1] <= ss[0];
    end

endmodule