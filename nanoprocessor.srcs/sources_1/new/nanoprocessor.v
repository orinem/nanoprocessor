`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company:     Pinhead Technologies
// Engineer:    Orin Eman
// Copyright (c) 2016 Orin Eman
// 
// Create Date: 07/27/2016 02:25:09 PM
// Design Name: 
// Module Name: nanoprocessor
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

module nanoprocessor(
    input         clk,          // Clock, assumed to be 100MHz
    input         ext_clock,    // External clock, 4MHz max, 100ns min high or low
    input         nirq,         // Interrupt Request
    output        int_ack,      // Interrupt Acknowledge
    output [10:0] addr,         // Program Address
    inout  [7:0]  data,         // Program data in and device I/O
    output        pgm_gate,     // Program Gate
    output        rw,           // 0 = Read, 1 = Write
    output [3:0]  deviceSelect, // Address for device I/O
    inout  [7:0]  deviceControl, // 7 I/O lines, bit 7 is used for Interrupt Enable
    output        synth_ext_clock
    );
    
    // 12.288 MHz clock
    wire locked, clk_12_288;
    clk_wiz_0 clk1(
        .clk_in1(clk),
        .clk_out1(clk_12_288),
        .locked(locked)
    );

    // Divide by 12.5, producing pulses 5 half clk_12_288 wide
    // HW was 4.9152MHz/5 - 12.288MHz/12.5 gives the same period
    (* DONT_TOUCH="true" *) reg [4:0] count12_5 = 5'b0_0000;
    reg [4:0] nextCount12_5;
    reg div12_5_0 = 1'b0;
    reg nextDiv12_5_0;
    reg div12_5_1 = 1'b0;
    reg nextDiv12_5_1;
    assign synth_ext_clock = div12_5_0 | div12_5_1;

    always @(*) begin
        nextCount12_5 = locked ? count12_5 + 2 : 5'b0_0000;
        nextDiv12_5_0 = 1'b0;
        nextDiv12_5_1 = 1'b0;

        case ( count12_5[4:0] )
            5'b1_0010:
                nextDiv12_5_0 = 1'b1;
            5'b1_0011, 5'b1_0100, 5'b1_0101: begin
                nextDiv12_5_0 = 1'b1;
                nextDiv12_5_1 = 1'b1;
            end
            5'b1_0110:
                nextDiv12_5_1 = 1'b1;
            5'b1_0111:
                nextCount12_5 = 5'b0_0000;
            5'b1_1000:
                nextCount12_5 = 5'b0_0001;
            default:
                ;
        endcase
    end
    
    always @(posedge clk_12_288) begin
        count12_5 <= nextCount12_5;
        div12_5_0 <= nextDiv12_5_0;
    end
    
    always @(negedge clk_12_288) begin
        div12_5_1 <= nextDiv12_5_1;
    end

    // External interface registers
    wire [7:0]  dataOut;
    reg         pgmGateOut = 1'b0;
    reg         rwOut= 1'b0;
    reg         intAckOut= 1'b0;
    reg  [7:0]  deviceControlOut = 8'b0111_1111;    // Float device control lines
    reg         dataOutEnable = 1'b0;
    reg         dataOutSelect = 1'b0;
    reg         deviceSelectEnable = 1'b0;
    reg  [7:0]  dataIn = 8'b0000_0000;
    // DONT_TOUCH to get sensible values in post-implementation timing simulation
    (* DONT_TOUCH="true" *) reg [7:0] instruction = 8'b0101_1111; // Init to NOP
    
    // Synchronize all external inputs with clk
    wire		sync_clock;
    wire        sync_nirq;
    wire [7:0]  sync_deviceControl;
    wire [7:0]  sync_data;
    (* keep_hierarchy = "yes" *) clock_sync syncExt(clk, ext_clock, sync_clock);
    (* keep_hierarchy = "yes" *) clock_sync syncIrq(clk, nirq, sync_nirq);
    generate
        genvar i;
        for ( i = 0; i <= 7; i = i + 1 )
        begin: dc_synchronizer
            (* keep_hierarchy = "yes" *) clock_sync dc(clk, deviceControl[i], sync_deviceControl[i]);
        end
        for ( i = 0; i <= 7; i = i + 1 )
        begin: data_synchronizer
            (* keep_hierarchy = "yes" *) clock_sync sd(clk, data[i], sync_data[i]);
        end
    endgenerate
    
    // Internal ROM
    (* mark_debug = "true" *) wire [7:0] ROMdata;
    blk_mem_gen_0 ROM(
        .addra( {4'b0000, addr[8:0]}),
        .clka(clk),
        .douta(ROMdata)
    );

    // Register interface
    wire [7:0]  regDataOut;
    wire [7:0]  a;
    wire        eOut;
    wire        ltOut;
    wire        eqOut;
    wire        zOut;
    wire [3:0]  index;
    wire        execute;
    reg  [3:0]  regControl = `REG_NOP;
    
    // The registers...
    registers regs(
        .dataIn(dataIn),
        .dataOut(regDataOut),
        .addr(instruction[3:0]),
        .a(a),
        .e(eOut),
        .clk(clk),
        .ctrl(regControl),
        .execute(execute),
        .lt(ltOut),
        .eq(eqOut),
        .z(zOut),
        .index(index));

    // Pipeline registers for 'flags'
    (* DONT_TOUCH="true" *) reg e = 1'b0;
    (* DONT_TOUCH="true" *) reg lt = 1'b0;
    (* DONT_TOUCH="true" *) reg eq = 1'b0;
    (* DONT_TOUCH="true" *) reg z = 1'b0;

    // Program Counter
    (* mark_debug = "true" *) reg  [10:0] pc = 11'b000_0000_0000;
    reg  [10:0] srr;    // Subroutine return address
    reg  [10:0] irr;    // Interrupt return address

    // Interrupt handling
    reg  check_irq = 1'b0;
    reg  interrupt_requested = 1'b0;
    
    // Program Memory interface
    reg  readROM = 1'b0;
    
    // State machine -
    // With the exception of INTERRUPT, they
    // typically execute in order.
    localparam
        RESET =         4'b0000,
        FETCH =         4'b0001,
        DECODE =        4'b0011,
        DELAY1 =        4'b0010,
        WAIT1 =         4'b0110,
        EXECUTE_FETCH = 4'b0111,
        EXECUTE_INCPC = 4'b0101,
        EXECUTE =		4'b0100,
        EXECUTE_SKIP =	4'b1100,
        WAIT2 =			4'b1000,
        INTERRUPT =     4'b1001;

    //(* DONT_TOUCH="true" *)
    reg  [3:0] state = RESET;
    reg [3:0] nextState;
    assign execute = (state[3:0] == EXECUTE);  // Registers are processed in EXECUTE state
    
    // Hook up IO
    assign pgm_gate = pgmGateOut;
    assign int_ack = intAckOut;
    assign rw = rwOut;
    assign addr = pc;
    assign dataOut = dataOutSelect ? regDataOut : ROMdata;
    
    generate
        for ( i = 0; i <= 3; i = i + 1 )
        begin: ds_driver
            // Device Select always comes from instruction[3:0], so hook it up directly
            // Careful to disable before a new instruction is read...
            output_bit ds(instruction[i], deviceSelect[i], deviceSelectEnable);
        end

        //for ( i = 0; i <= 10; i = i + 1 )
        //begin: addr_driver
        //    // Address always comes from the PC, might as well always enable the output
        //     output_bit addr(pc[i], addr[i], 1'b1);
        //end

        for ( i = 0; i <= 7; i = i + 1 )
        begin: dc_driver
            // Device Control output bits are always enabled
            inout_bit dc(deviceControlOut[i], deviceControl[i]);
        end

        for ( i = 0; i <= 7; i = i + 1 )
        begin: data_driver
            output_bit data(dataOut[i], data[i], dataOutEnable);
        end
    endgenerate

    // State machine
    // It is suggested in the literature that the next state be calculated in a separate always @(*) block
    // and the always @(posedge clk) block only update state/outputs.  But the result is an always @(*) block that looks
    // exactly like the one below, but with all the outputs replaced by a next variable and an always @(posedge clk)
    // block that merely assigns the next variables to the corresponding variable.  I fail to see the benefit.
    reg [1:0] pcIncr, nextPCIncr;
    reg [10:0] nextPC;
    reg        loadPC;
    always @(posedge clk)
    begin
        // Defaults
        nextState = state;
        nextPCIncr = 2'b00;
        nextPC = pc + pcIncr;
        loadPC = pcIncr[1] | pcIncr[0];

        // Pipelined update of PC
        // The states following setting of nextPCIncr will see the old pc value;
        // these states are DECODE, EXECUTE_INCPC, EXECUTE_SKIP.

        case ( state )
            RESET: begin
                // Wait for the external clock to go high then low before reading the first instruction
                if ( locked & sync_clock )
                    nextState = WAIT2;
                nextPC = 11'b000_0000_0000;         //!!! Is this the correct address at reset???
                loadPC = 1'b1;

                instruction <= 8'b0101_1111;        // Init to NOP
                regControl <= `REG_NOP;
                deviceControlOut <= 8'b0111_1111;   // Float device control lines
                deviceSelectEnable <= 1'b0;         // Float device select lines
                dataOutEnable <= 1'b0;              // Float data lines
                dataOutSelect <= 1'b0;              // Select ROMdata
                pgmGateOut <= 1'b0;
                intAckOut <= 1'b0;
                check_irq <= 1'b0;
                if ( !sync_nirq )                   // 3455A inguard uses an interrupt on power up
                    interrupt_requested <= 1'b1;
            end

            // Interrupt Vector Fetch
            INTERRUPT: begin
                if (!sync_clock) begin
                    dataIn <= sync_data;
                end
                else begin
                    nextState = WAIT2;
                    nextPC = {3'b000, dataIn[7:0]};
                    loadPC = 1'b1;

                    irr <= pc;
                end
           end
            
            // Instruction Fetch
            FETCH: begin
                if ( sync_clock )
                begin
                    nextState = DECODE;
                    nextPCIncr[0] = 1'b1;   // PC will be incremented on next clock

                    instruction <= ROMdata; // Read instruction from the ROM                
                    pgmGateOut <= 1'b0;
                end
            end
            
            // Partially decode instruction to determine whether a second ROM
            // read is required, to set the register control lines and to
            // prepare output data.
            // Note: PC is incremented in this state
            DECODE: begin
                nextState = DELAY1;

                // Capture current flags
                e <= eOut;
                lt <= ltOut;
                eq <= eqOut;
                z <= zOut;

                readROM <= 1'b0;            // Assume no ROM data for the instruction
                deviceSelectEnable <= 1'b0; // Assume not inputing/outputing data
                check_irq <= 1'b1;          // Check for IRQ (will be cleared for a DSI instruction)

                case ( instruction[7:3] )
                    // INB, DEB, IND, DEX, CLA, CMA, RSA, LSA
                    5'b0000_0:
                        regControl <= `REG_ALU;

                    // SGT, SLT, SEQ, SAZ, SLE, SGE, SNE, SAN
                    // 5'b0000_1: ;
                    
                    // SBS
                    // 5'b0001_0: ;

                    // SFS                        
                    // 5'b0001_1: ;
                    
                    // SBN
                    5'b0010_0:
                        regControl <= `REG_SBN;
                    
                    // STC
                    // 5'b0010_1: ;
                    
                    // SBZ
                    // 5'b0011_0 ;
                    
                    // SFZ
                    // 5'b0011_1: ;
                    
                    // INA
                    5'b0100_0, 5'b0100_1: begin
                        deviceSelectEnable <= 1'b1;
                        rwOut <= 1'b0;
                    end

                    // OTA
                    5'b0101_0, 5'b0101_1: begin
                        // Note OTA 15 is defined to be NOP,
                        if (instruction[3:0] != 4'b1111)
                        begin
                            rwOut <= 1'b1;
                            deviceSelectEnable <= 1'b1;
                            dataOutEnable <= 1'b1;
                            dataOutSelect <= 1'b1;  // Select regDataOut
                            regControl <= `REG_OTA;
                        end
                    end
                    
                    // LDA
                    5'b0110_0, 5'b0110_1:
                        regControl <= `REG_LDA;
                    
                    // STA
                    5'b0111_0, 5'b0111_1:
                        regControl <= `REG_STA;

                    // JMP/JSB, JAI/JAS
                    // Even though they don't use the second instruction byte,
                    // JAS at least increments the PC before saving it in SRR
                    5'b1000_0, 5'b1000_1, 5'b1001_0, 5'b1001_1:
                        readROM <= 1'b1;
                    
                    // CBN
                    5'b1010_0:
                        regControl <= `REG_CBN;
                        
                    // CLC/DSI
                    5'b1010_1:
                        if ( instruction[2:0] == 3'b111 )
                            check_irq <= 1'b0;

                    // RTI, RTE, STE, CLE
                    5'b1011_0:
                        if ( instruction[2:0] == 3'b100 )
                            regControl <= `REG_STE;
                        else if ( instruction[2:0] == 3'b101 )
                            regControl <= `REG_CLE;
                            
                    // RTS/RSE
                    // 5'b1011_1: ;

                    // OTR, LDR
                    5'b1100_0, 5'b1100_1: begin
                        readROM <= 1'b1;
                        if ( instruction[3:0] == 4'b1111 )
                            regControl <= `REG_LDR;
                        else begin
                            rwOut <= 1'b1;
                            deviceSelectEnable <= 1'b1;
                            dataOutEnable <= 1'b1;
                            dataOutSelect <= 1'b0;
                        end
                    end

                    // STR
                    5'b1101_0, 5'b1101_1: begin
                        readROM <= 1'b1;
                        regControl <= `REG_STR;
                    end
                    
                    // LDI
                    5'b1110_0, 5'b1110_1: 
                        regControl <= `REG_LDI;
                    
                    // STI
                    5'b1111_0, 5'b1111_1: 
                        regControl <= `REG_STI;
                    
                    default: ;
                endcase
            end
            
            // Extra state to delay before enabling address outputs           
            DELAY1:
                nextState = WAIT1;

            // Waiting for second clock for execute phase of instruction
            WAIT1:
                if (!sync_clock) begin
                    nextState = EXECUTE_FETCH;
                    pgmGateOut <= readROM;
                end
 
            // Execute phase of instruction
            EXECUTE_FETCH: begin
                // Wait for external clock high
                 if ( sync_clock )
                    nextState = EXECUTE;

                // Check for IRQ if not DSI instruciton
                interrupt_requested <= (check_irq & !sync_nirq);

                //  Read data from bus if necessary (see FETCH state)
                if ( readROM )
                    if ( sync_clock ) begin
                        nextState = EXECUTE_INCPC;
                        nextPCIncr[0] = 1'b1;        // Schedule PC increment

                        dataIn <= ROMdata;
                        readROM <= 1'b0;
                        pgmGateOut <= 1'b0;
                    end
             end
            
            // Increment PC before executing the instruction
            EXECUTE_INCPC: begin
                nextState = EXECUTE;
            end

            // Execute instruction
            EXECUTE: begin
                nextState = EXECUTE_SKIP;

                // Execute input to registers is set, so registers are also updated at this time
                // Handle jumps and conditional instructions here
                case ( instruction[7:3] )
                    5'b0000_1: begin
                        case ( instruction[2:0] )
                            3'b000: // SGT
                                nextPCIncr[1] = (~lt & ~eq);
                            3'b0001: // SLT
                                nextPCIncr[1] = lt;
                            3'b010:  // SEQ
                                nextPCIncr[1] = eq;
                            3'b011:  // SAZ
                                nextPCIncr[1] = z;
                            3'b100:  // SLE
                                nextPCIncr[1] = (lt | eq);
                            3'b101:  // SGE
                                nextPCIncr[1] = ~lt;
                            3'b110:  // SNE
                                nextPCIncr[1] = ~eq;
                            3'b111:  // SAN
                                nextPCIncr[1] = ~z;
                        endcase
                    end

                    // SBS
                    5'b0001_0:
                        nextPCIncr[1] = a[instruction[2:0]];

                    // SFS/SES
                    5'b0001_1:
                        if ( instruction[2:0] == 3'b111 )
                            nextPCIncr[1] = e;
                        else
                            nextPCIncr[1] = sync_deviceControl[instruction[2:0]];
                            
                    // STC/ENI
                    5'b0010_1:
                        deviceControlOut[instruction[2:0]] <= 1'b1;

                    // SBZ
                    5'b0011_0:
                        nextPCIncr[1] = ~a[instruction[2:0]];

                    // SFZ/SEZ
                    5'b0011_1:
                        if ( instruction[2:0] == 3'b111 )
                            nextPCIncr[1] = ~e;
                        else
                            nextPCIncr[1] = ~sync_deviceControl[instruction[2:0]];

                    // JMP/JSB
                    5'b1000_0, 5'b1000_1: begin
                        nextPC = {instruction[2:0], dataIn[7:0]};
                        loadPC = 1'b1;

                        if ( instruction[3] )
                            srr <= pc;
                    end

                    // JAI, JAS
                    5'b1001_0, 5'b1001_1: begin
                        begin
                            // JAI, JAS
                            nextPC = {index[2:0], a[7:0]};
                            loadPC = 1'b1;

                            // If instruction[3] OR R0[3] is set, it's JAS
                            if ( index[3] )
                                srr <= pc;
                        end
                    end

                    // CLC/DSI
                    5'b1010_1:
                        deviceControlOut[instruction[2:0]] <= 1'b0;

                    // RTI, RTE, STE, CLE
                    5'b1011_0: begin
                        if ( instruction[2:0] == 3'b000 ) begin
                            nextPC = irr;
                            loadPC = 1'b1;
                        end
                        else if ( instruction[2:0] == 3'b001 ) begin
                            nextPC = irr;
                            loadPC = 1'b1;

                            deviceControlOut[7] <= 1'b1;
                        end
                    end

                    // RTS/RSE
                    5'b1011_1: begin
                        nextPC = srr;
                        loadPC = 1'b1;

                        if ( instruction[0] )
                            deviceControlOut[7] <= 1'b1;
                    end
                endcase

            end

            // Extra state to delay before enabling address outputs           
            // PC will be updated below if PCincr was set by EXECUTE state

            EXECUTE_SKIP: begin
                nextState = WAIT2;
            end

            // Wait for external clock low to read next instruction
            WAIT2: begin
                // Instruction execution is finished, get ready for the next instruction
                regControl <= `REG_NOP;

                // Reset the data bus
                readROM <= 1'b1;
                rwOut <= 1'b1;
                deviceSelectEnable <= 1'b0;
                dataOutSelect <= 1'b0;
                dataOutEnable <= 1'b0;

                if (!sync_clock)
                begin
                    // Either take an interrupt or continue onto the next instruction
                    if (interrupt_requested)
                    begin
                        nextState = INTERRUPT;

                        intAckOut <= 1'b1;
                        interrupt_requested <= 1'b0;
                    end
                    else begin
                        nextState = FETCH;

                        pgmGateOut <= 1'b1;
                        intAckOut <= 1'b0;
                    end
                end
            end
            
            default: ;
        endcase

        if (loadPC)
        	pc <= nextPC;
        pcIncr <= nextPCIncr;
        state <= nextState;
     end
endmodule
