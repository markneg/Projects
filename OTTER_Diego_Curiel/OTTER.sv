`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: California Polytechnic University, San Luis Obispo
// Engineer: Diego Renato Curiel
// Create Date: 03/02/2023 04:17:51 PM
// Module Name: OTTER
//////////////////////////////////////////////////////////////////////////////////

module OTTER(
    input logic RST,
    input logic [31:0] IOBUS_IN,
    input logic CLK,
    output logic IOBUS_WR,
    output logic [31:0] IOBUS_OUT,
    output logic [31:0] IOBUS_ADDR
    );
    
    //NOTE ABOUT METHODOLOGY FOR CREATING TOP-LEVEL MODULE:
    //I decided to look at the OTTER diagram and create logic (connecting wires)
    //from left to right. This way, I was able to methodically move through the diagram,
    //connecting PC to Memory, then Memory to Reg File, Reg File Mux, and Immediate 
    //Generator, then connecting ALU, Branch Address Generator, then Branch Condition Generator,
    //and finally connecting the Control Unit consisting of the FSM and Decoder. It made
    //the process simpler, and allowed for me to create a "flow" in the SystemVerilog code.
    //I did my best to keep the name of my lgoic consistent to the names that are in the OTTER
    //diagram, and made all interconnecting wires lowercase so as to not confuse them with I/O.
    
    //Create logic for PC; connecting wires to Memory module and RegFile Mux
    logic pc_rst, pc_write;
    logic [2:0] pc_source;
    logic [31:0] pc_out, pc_out_inc, jalr, branch, jal;
    
    //Instantiate the PC and connect relevant I/O
    PC OTTER_PC(.CLK(CLK), .RST(pc_rst), .PC_WRITE(pc_write), .PC_SOURCE(pc_source),
        .JALR(jalr), .JAL(jal), .BRANCH(branch), .MTVEC(32'b0), .MEPC(32'b0),
        .PC_OUT(pc_out), .PC_OUT_INC(pc_out_inc));
    
    //Create logic for Memory module; conecting wires to RegFile
    //Immediate Generator, and RegFile Mux    
    logic [13:0] addr1;
    assign addr1 = pc_out[15:2];
    logic mem_rden1, mem_rden2, mem_we2;
    logic [31:0] dout2, ir;
    logic sign;
    assign sign = ir[14];
    logic [1:0] size;
    assign size = ir[13:12];
    
    //Instantiate the Memory module and connect relevant I/O    
    Memory OTTER_MEMORY(.MEM_CLK(CLK), .MEM_RDEN1(mem_rden1), .MEM_RDEN2(mem_rden2), 
        .MEM_WE2(mem_we2), .MEM_ADDR1(addr1), .MEM_ADDR2(IOBUS_ADDR), .MEM_DIN2(IOBUS_OUT), .MEM_SIZE(size),
         .MEM_SIGN(sign), .IO_IN(IOBUS_IN), .IO_WR(IOBUS_WR), .MEM_DOUT1(ir), .MEM_DOUT2(dout2));
    
    //Create logic for the RegFile, Immediate Generator, Branch Addresss 
    //Generator, and ALU MUXes     
    logic reg_wr;
    logic [1:0] rf_wr_sel;
    logic [4:0] reg_adr1;
    assign reg_adr1 = ir[19:15]; 
    logic [4:0] reg_adr2;
    assign reg_adr2 = ir[24:20]; 
    logic [4:0] reg_wa;
    assign reg_wa = ir[11:7];
    logic [24:0] imgen_ir;
    assign imgen_ir = ir[31:7];
    logic [31:0] wd, rs1;
    
    //Instantiate RegFile Mux, connect all relevant I/O
    FourMux OTTER_REG_MUX(.SEL(rf_wr_sel), .ZERO(pc_out_inc), .ONE(32'b0), .TWO(dout2), .THREE(IOBUS_ADDR),
        .OUT(wd));
    
    //Instantiate RegFile, connect all relevant I/O    
    REG_FILE OTTER_REG_FILE(.CLK(CLK), .EN(reg_wr), .ADR1(reg_adr1), .ADR2(reg_adr2), .WA(reg_wa), 
        .WD(wd), .RS1(rs1), .RS2(IOBUS_OUT));
    
    //Create logic for Immediate Generator outputs and BAG and ALU MUX inputs    
    logic [31:0] Utype, Itype, Stype, Btype, Jtype;
    
    //Instantiate Immediate Generator, connect all relevant I/O
    ImmediateGenerator OTTER_IMGEN(.IR(imgen_ir), .U_TYPE(Utype), .I_TYPE(Itype), .S_TYPE(Stype),
        .B_TYPE(Btype), .J_TYPE(Jtype));
    
    //Instantiate Branch Address Generator, connect all relevant I/O    
    BAG OTTER_BAG(.RS1(rs1), .I_TYPE(Itype), .J_TYPE(Jtype), .B_TYPE(Btype), .FROM_PC(pc_out),
         .JAL(jal), .JALR(jalr), .BRANCH(branch));
    
    //Create logic for ALU
    logic alu_src_a;
    logic [1:0] alu_src_b;
    logic [3:0] alu_fun;
    logic [31:0] srcA, srcB;
    
    //Instantiate ALU two-to-one Mux, ALU four-to-one MUX,
    //and ALU; connect all relevant I/O     
    TwoMux OTTER_ALU_MUXA(.ALU_SRC_A(alu_src_a), .RS1(rs1), .U_TYPE(Utype), .SRC_A(srcA));
    FourMux OTTER_ALU_MUXB(.SEL(alu_src_b), .ZERO(IOBUS_OUT), .ONE(Itype), .TWO(Stype), .THREE(pc_out), .OUT(srcB));
    ALU OTTER_ALU(.SRC_A(srcA), .SRC_B(srcB), .ALU_FUN(alu_fun), .RESULT(IOBUS_ADDR));
    
    //Create logic for Branch Condition Generator
    logic br_eq, br_lt, br_ltu;    
    
    //Instantiate Branch Condition Generator, connect all 
    //relevant I/O
    BCG OTTER_BCG(.RS1(rs1), .RS2(IOBUS_OUT), .BR_EQ(br_eq), .BR_LT(br_lt), .BR_LTU(br_ltu));
    
    //Create logic for FSM and Decoder
    logic ir30;
    assign ir30 = ir[30];
    logic [6:0] opcode;
    assign opcode = ir[6:0];
    logic [2:0] funct;
    assign funct = ir[14:12]; 
    
    //Instantiate Decoder, connect all relevant I/O
    CU_DCDR OTTER_DCDR(.IR_30(ir30), .IR_OPCODE(opcode), .IR_FUNCT(funct), .BR_EQ(br_eq), .BR_LT(br_lt),
     .BR_LTU(br_ltu), .ALU_FUN(alu_fun), .ALU_SRCA(alu_src_a), .ALU_SRCB(alu_src_b), .PC_SOURCE(pc_source),
      .RF_WR_SEL(rf_wr_sel));
    
    //Instantiate FSM, connect all relevant I/O
    CU_FSM OTTER_FSM(.CLK(CLK), .RST(RST), .IR_OPCODE(opcode), 
        .PC_WRITE(pc_write), .REG_WRITE(reg_wr), .MEM_WE2(mem_we2), 
        .MEM_RDEN1(mem_rden1), .MEM_RDEN2(mem_rden2), .rst(pc_rst));
    
endmodule

