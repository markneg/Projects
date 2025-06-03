`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:  J. Callenes
// 
// Create Date: 01/04/2019 04:32:12 PM
// Design Name: 
// Module Name: PIPELINED_OTTER_CPU
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

typedef struct packed{
    logic [6:0] opcode;
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;
    //logic rs1_used; // dont know use
    //logic rs2_used; // don't know use
    //logic rd_used;  // don't know use
    logic memWE2;
    logic memRDEN2;
    logic RF_WE;
    logic [1:0] RF_SEL;
    logic [1:0] mem_size;
    logic mem_sign;
    logic [31:0] pc_plus4;
} instr_t;

module OTTER_MCU(
    input CLK,
    input INTR,
    input cpu_reset,
    input [31:0] IOBUS_IN,
    output [31:0] IOBUS_OUT,
    output [31:0] IOBUS_ADDR,
    output logic IOBUS_WR   
);           
    // Final list of logic wires
    // in all stages
    instr_t de_instr, ex_instr, mem_instr, wb_instr;
    logic [1:0] op1_sel, op2_sel;
    logic stall, flush;
    
    // IF
    logic [31:0] if_pc, if_pc_plus4, if_ir;
    logic if_pc_we;
    logic [31:0] if_w0, if_w1, if_w2, if_w3, if_w4, if_w5, if_w6, if_w7;
    logic if_update, if_hit, if_miss, haz_stall, DM_Cache_stall; 
    
    // DEC
    logic [31:0] de_ir, de_pc, de_rs1, de_rs2,  
    de_Jtype, de_Btype, de_Itype, de_Utype, de_Stype;
    logic [1:0]de_srcA_SEL, de_RF_SEL;
    logic [2:0] de_srcB_SEL; 
    logic de_RF_WE, de_memWE2, de_memRDEN2; 
    logic [31:0] de_jal, de_branch, de_jalr;
    logic [3:0] de_alu_fun;
    
    // Ex
    logic [31:0] ex_rs1, ex_rs2, ex_rs1_forwarded, ex_rs2_forwarded, ex_alu_result, 
    ex_Utype, ex_Itype, ex_Stype, ex_Jtype, ex_Btype, ex_pc, ex_reg_rs1, ex_reg_rs2, ex_jal, ex_branch, ex_jalr;
    logic [3:0] ex_alu_fun;
    logic [1:0]ex_srcA_SEL;
    logic [2:0] ex_srcB_SEL, ex_PC_SEL, ex_ir14to12; 
    
    // mem
    logic [31:0] mem_alu_result, mem_rs2, mem_DOUT2;
    
    // wb
    logic [31:0] wb_alu_result, wb_DOUT2, reg_mux;
    
    
    
   // define hazard detection unit
    HazardUnit hazard(.opcode(ex_instr.opcode), .de_adr1(de_ir[19:15]), .de_adr2(de_ir[24:20]), 
    .ex_rd(ex_instr.rd_addr), .mem_rd(mem_instr.rd_addr), .wb_rd(wb_instr.rd_addr), .pc_source(ex_PC_SEL), 
    .mem_regWrite(mem_instr.RF_WE), .wb_regWrite(wb_instr.RF_WE), .fsel1(op1_sel), .fsel2(op2_sel), 
    .load_use_haz(haz_stall), .control_haz(), .flush(flush), .ex_adr1(ex_instr.rs1_addr), .ex_adr2(ex_instr.rs2_addr));
    
    // set stall if either haz_stall or cache_stall happens
    assign stall = (haz_stall || DM_Cache_stall);
   
//==== Instruction Fetch ===========================================
    // send struct and instruction to next stage if not a flush and not a stall
    always_ff @(posedge CLK) begin
        if (!stall) begin
            de_pc <= if_pc;
            //de_ir <= if_ir;
            de_instr.pc_plus4 <= if_pc_plus4; 
        end
    end
    
    always_comb begin
        if (flush) begin
            de_ir = 0;
         //   de_instr = '0;  // Clear the instruction struct too
       end else
            de_ir = if_ir;
    end
    
    assign if_pc_we = !stall;
    assign if_mem_rden1 = !stall;
    
    //Define Program Counter
    PC PC_(.PC_RST(reset), .PC_WE(if_pc_we), .PC_JALR(ex_jalr), .PC_BRANCH(ex_branch), 
    .PC_JAL(ex_jal), .PC_SEL(ex_PC_SEL), .PC_CLK(CLK), .PC_Plus4(if_pc_plus4), .PC_COUNT(if_pc));
    
    // Define Memory
    // IF step: rden1, addr1, dout1
    // MEM step: rden2, we2, addr2, alu_result, rs2, mem_size, mem_sign, dout2, iobus_in, iobus_wr
    Memory MEM(.MEM_CLK(CLK), .MEM_RDEN1(if_mem_rden1), .MEM_RDEN2(mem_instr.memRDEN2), 
    .MEM_WE2(mem_instr.memWE2), .MEM_ADDR1(if_pc), .MEM_ADDR2(mem_alu_result), .MEM_DIN2(mem_rs2), 
    .MEM_SIZE(mem_instr.mem_size), .MEM_SIGN(mem_instr.mem_sign), .IO_IN(IOBUS_IN), .IO_WR(IOBUS_WR), 
    //.MEM_DOUT1(if_ir),
    .w0(if_w0), .w1(if_w1), .w2(if_w2), .w3(if_w3), .w4(if_w4), .w5(if_w5), .w6(if_w6), .w7(if_w7),
    .MEM_DOUT2(wb_DOUT2));
    
    //Implement IM Cache (Cache and FSM)
    DM_Cache DM_Cache(.PC(if_pc), .CLK(CLK), .update(if_update),
    .w0(if_w0), .w1(if_w1), .w2(if_w2), .w3(if_w3), .w4(if_w4), .w5(if_w5), .w6(if_w6), .w7(if_w7),
    .rd(if_ir), .hit(if_hit), .miss(if_miss), .DM_Cache_rden(if_mem_rden1),
    .flush(flush)
    );
    
    DM_CacheFSM DM_CacheFSM(.hit(if_hit), .miss(if_miss), .CLK(CLK), .RST(cpu_reset),
    .update(if_update), .flush(flush), .pc_stall(DM_Cache_stall));
     
//==== Instruction Decode ===========================================
    /*
    assign de_instr.rs1_used=    de_instr.rs1_addr != 0       // changed from rs1 to rs1.addr
                                && de_instr.opcode != 7'b0110111 //LUI
                                && de_instr.opcode != 7'b0010111 //AUIPC
                                && de_instr.opcode != 7'b1101111;//JAL
   */
    always_ff @(posedge CLK) begin
        if (haz_stall) begin
            ex_instr <= 0;
        end
        else if (!stall) begin
            ex_pc <= de_pc;
            
            ex_instr <= de_instr;
            ex_instr.opcode <= de_ir[6:0];
            ex_instr.rs1_addr <= de_ir[19:15];
            ex_instr.rs2_addr <= de_ir[24:20];
            ex_instr.rd_addr <= de_ir[11:7];
            ex_instr.mem_size <= de_ir[13:12];
            ex_instr.mem_sign <= de_ir[14];
            ex_instr.RF_SEL <= de_RF_SEL;
            ex_instr.RF_WE <= de_RF_WE;
            ex_instr.memWE2 <= de_memWE2;
            ex_instr.memRDEN2 <= de_memRDEN2;
            
            ex_srcA_SEL <= de_srcA_SEL ;
            ex_srcB_SEL <= de_srcB_SEL;
            ex_reg_rs1 <= de_rs1;
            ex_reg_rs2 <= de_rs2;
            ex_Utype <= de_Utype;
            ex_Itype <= de_Itype;
            ex_Stype <= de_Stype;
            ex_Jtype <= de_Jtype;
            ex_Btype <= de_Btype;
            ex_alu_fun <= de_alu_fun;
            ex_ir14to12 <= de_ir[14:12];
        end 
      end        


    // Define Reg File
	Reg_File REGFile(.REG_en(wb_instr.RF_WE), .REG_adr1(de_ir[19:15]), .REG_adr2(de_ir[24:20]), 
    .REG_w_adr(wb_instr.rd_addr), .REG_w_data(reg_mux), .REG_CLK(CLK), .REG_rs1(de_rs1), 
    .REG_rs2(de_rs2));
    
    // Define DCDR
    CUDCDR DCDR(.ir6to0(de_ir[6:0]), .ir14to12(de_ir[14:12]), 
    .CUDCDR_ir30(de_ir[30]), .CUDCDR_ALU_FUN(de_alu_fun), 
    .CUDCDR_srcA_SEL(de_srcA_SEL), .CUDCDR_srcB_SEL(de_srcB_SEL),
    .CUDCDR_RF_SEL(de_RF_SEL), 
    // other part from FSM
    .CUFSM_RST(cpu_reset), 
    .CUFSM_PC_WE(PC_WE), .CUFSM_RF_WE(de_RF_WE), .CUFSM_memWE2(de_memWE2), 
    .CUFSM_memRDEN1(memRDEN1), .CUFSM_memRDEN2(de_memRDEN2), .CUFSM_reset(reset));
    
    // Define Immediate Generator
    Imme_Gen IMMEGEN(.Imme_Gen_Instruction(de_ir[31:7]), .Imme_Gen_U_type(de_Utype), 
    .Imme_Gen_I_type(de_Itype), .Imme_Gen_S_type(de_Stype), .Imme_Gen_J_type(de_Jtype), 
    .Imme_Gen_B_type(de_Btype));
	
//==== Execute ======================================================
// has ALU
    
    // Define Branch Condition Generator
    // note rs1 and rs2 gained from execute step but outputs go to decode step
    // second note: making another decoder so doesnt go to decode step now
    BRANCH_COND_GEN CONDGEN(.CONDGEN_rs1(ex_rs1), .CONDGEN_rs2(ex_rs2), 
    .CONDGEN_opcode(ex_instr.opcode), .CONDGEN_ir14to12(ex_ir14to12), .CONDGEN_pc_sel(ex_PC_SEL));
    
    // Define Branch Addr Generator
    BRANCH_ADDR_GEN ADDRGEN(.ADDRGEN_PC(ex_pc), .ADDRGEN_J_Type(ex_Jtype), 
    .ADDRGEN_B_Type(ex_Btype), .ADDRGEN_I_Type(ex_Itype), .ADDRGEN_rs1(ex_rs1), 
    .ADDRGEN_jal(ex_jal), .ADDRGEN_branch(ex_branch), .ADDRGEN_jalr(ex_jalr));
     
    // Creates a RISC-V ALU DONE
    ALU ALU(.ALU_srcA(ex_rs1_forwarded), .ALU_srcB(ex_rs2_forwarded), .ALU_FUN(ex_alu_fun), 
    .ALU_result(ex_alu_result));
    
    always_ff @(posedge CLK) begin
            mem_instr <= ex_instr;
            mem_alu_result <= ex_alu_result;    //fix by moving all logic definitions to top
            mem_rs2 <= ex_rs2;
    end
    
    // create ALU Muxs
    always_comb begin
        // mux for data forward
        case(op1_sel)
            2'b00: ex_rs1 = ex_reg_rs1;
            2'b01: ex_rs1 = mem_alu_result;
            2'b10: ex_rs1 = reg_mux;
            default: ex_rs1 = 32'h0BAD0BAD;
        endcase
        case(op2_sel)
            2'b00: ex_rs2 = ex_reg_rs2;
            2'b01: ex_rs2 = mem_alu_result;
            2'b10: ex_rs2 = reg_mux;
            //3'b011: ex_rs2 = ;
            //3'b100: ex_rs2_forwarded = csr_RD; dont need
            default: ex_rs2 = 32'h0BAD0BAD;
        endcase
        
        // mux for input to alu
        case(ex_srcA_SEL)
            2'b00: ex_rs1_forwarded = ex_rs1;
            2'b01: ex_rs1_forwarded = ex_Utype;
            2'b10: ex_rs1_forwarded = ~ex_rs1;
            default: ex_rs1_forwarded = 32'h0BAD0BAD;
        endcase
        case(ex_srcB_SEL)
            3'b000: ex_rs2_forwarded = ex_rs2;
            3'b001: ex_rs2_forwarded = ex_Itype;
            3'b010: ex_rs2_forwarded = ex_Stype;
            3'b011: ex_rs2_forwarded = ex_pc;
            //3'b100: ex_rs2_forwarded = csr_RD; dont need
            default: ex_rs2_forwarded = 32'h0BAD0BAD;
        endcase
    end


//==== Memory ======================================================
     
     
     
    // define memory using space from decode step
    // mem_alu_result -> MEM_ADDR2  INPUT
    // mem_rs2 -> write data         INPUT
    // dout2 -> mem_dout2           OUTPUT
    
    assign IOBUS_ADDR = mem_alu_result;
    assign IOBUS_OUT = mem_rs2;
    
    always_ff @(posedge CLK) begin
            wb_instr <= mem_instr;
            wb_alu_result <= mem_alu_result;
            //wb_DOUT2 <= mem_DOUT2;
    end
     
//==== Write Back ==================================================
     
    always_comb begin
        case(wb_instr.RF_SEL)
            2'b00: reg_mux = wb_instr.pc_plus4;
            //2'b01: reg_mux = csr_RD;
            2'b10: reg_mux = wb_DOUT2;
            2'b11: reg_mux = wb_alu_result;
            default: reg_mux = 32'h0BAD0BAD;
        endcase
    end
        
endmodule