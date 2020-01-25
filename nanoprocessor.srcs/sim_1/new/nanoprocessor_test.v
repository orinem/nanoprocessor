`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company:     Pinhead Technologies
// Engineer:    Orin Eman
// Copyright (c) 2016 Orin Eman
// 
// Create Date: 08/02/2016 03:06:55 PM
// Design Name: 
// Module Name: nanoprocessor_test
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


module nanoprocessor_test(
);
    reg clk = 1'b0;
    reg ext_clock = 1'b0;
    reg nreset = 1'b0;
    reg reset_acked = 1'b0;
    
    always #5 clk = ~clk;   // 100 MHz clock
    
    always begin
        // Realistic for the HP 3455A
        //#1017 ext_clock = 1;
        //#203 ext_clock = 0;
        // As fast as possible for simulation
        #101 ext_clock = ~ext_clock;
    end

    wire        int_ack;
    wire [7:0]  data;
    wire        pgm_gate;
    wire        rw;
    wire [10:0] ROMaddr;
    wire [7:0]	ROMdata;

    wire  [7:0] deviceControl;
    wire  [3:0] deviceSelect;
    wire        synth_ext_clock;

    nanoprocessor processor(
        .clk(clk),
        .ext_clock(ext_clock),
        .nirq(nreset),
        .int_ack(int_ack),
        .addr(ROMaddr),
        .data(data),
        .pgm_gate(pgm_gate),
        .rw(rw),
        .deviceSelect(deviceSelect),
        .deviceControl(deviceControl),
        .synth_ext_clock(synth_ext_clock)
    );
    

    PULLUP PULLUP_DC0(.O(deviceControl[0]));
    PULLUP PULLUP_DC1(.O(deviceControl[1]));
    PULLUP PULLUP_DC2(.O(deviceControl[2]));
    PULLUP PULLUP_DC3(.O(deviceControl[3]));
    PULLUP PULLUP_DC4(.O(deviceControl[4]));
    PULLUP PULLUP_DC5(.O(deviceControl[5]));
    PULLUP PULLUP_DC6(.O(deviceControl[6]));
    PULLUP PULLUP_DC7(.O(deviceControl[7]));
    
    PULLUP PULLUP_DATA0(.O(data[0]));
    PULLUP PULLUP_DATA1(.O(data[1]));
    PULLUP PULLUP_DATA2(.O(data[2]));
    PULLUP PULLUP_DATA3(.O(data[3]));
    PULLUP PULLUP_DATA4(.O(data[4]));
    PULLUP PULLUP_DATA5(.O(data[5]));
    PULLUP PULLUP_DATA6(.O(data[6]));
    PULLUP PULLUP_DATA7(.O(data[7]));
    
    PULLUP PULLUP_DS0(.O(deviceSelect[0]));
    PULLUP PULLUP_DS1(.O(deviceSelect[1]));
    PULLUP PULLUP_DS2(.O(deviceSelect[2]));
    PULLUP PULLUP_DS3(.O(deviceSelect[3]));
    
    PULLDOWN PULLDOWN_RW(.O(rw));
    PULLDOWN PULLDOWN_PGM_GATE(.O(pgm_gate));
    PULLDOWN PULLDOWN_INT_ACK(.O(int_ack));
    PULLDOWN PULLDOWN_SYNTH_EXT_CLOCK(.O(synth_ext_clock));

    // Drive 0xFD on data bus on int ack during reset
    assign data = //pgm_gate ? ROMdata :
        ((!pgm_gate & !nreset & int_ack) ? 8'b1111_1101 : 8'bzzzz_zzzz);
        
    always @(posedge clk)
    begin
        // Reset done by interrupt - clear at end of int ack.
        if (int_ack)
        begin
            if (!nreset)
                reset_acked <= 1'b1;
        end
        else begin
            if (reset_acked)
                nreset <= 1'b1;
        end
    end
    
endmodule
