`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/12/2025 12:52:21 AM
// Design Name: 
// Module Name: DM_Cache
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


module SA_Cache(
input [31:0] PC,
input CLK,
input update,
input SA_Cache_WE,
input SA_Cache_rden,
input logic [31:0] rw0,
input logic [31:0] rw1,
input logic [31:0] rw2,
input logic [31:0] rw3,
input logic [31:0] DIN2,
output logic [31:0] ww0,
output logic [31:0] ww1,
output logic [31:0] ww2,
output logic [31:0] ww3,
output logic [31:0] rd,
output logic hit,
output logic miss,
output logic wb_mem,
output logic [31:0] wb_adr
);
//parameter NUM_BLOCKS = 16;
parameter BLOCKS_PER_SET = 4;
parameter NUM_SETS = 4;
parameter BLOCK_SIZE = 4;
parameter SET_INDEX_SIZE = 2;
parameter WORD_OFFSET_SIZE = 2;
parameter BYTE_OFFSET = 2;
parameter TAG_SIZE = 32 - SET_INDEX_SIZE - WORD_OFFSET_SIZE - BYTE_OFFSET;

typedef struct {
    logic [31:0] data[4];
    logic [TAG_SIZE-1:0] tag;
    logic valid;
    logic dirty;
    logic [1:0] lru;
} cache_block;

cache_block cache[NUM_SETS][BLOCKS_PER_SET];

initial begin
    // iterate through sets
    for(int s = 0; s < NUM_SETS; s++) begin
        // iterate through blocks
        for(int b = 0; b < BLOCKS_PER_SET; b++) begin //initializing RAM to 0
            cache[s][b].tag = 0;
            cache[s][b].valid = 0;
            cache[s][b].dirty = 0;
            cache[s][b].lru = 0;
            // iterate through each word withing block
            for(int w = 0; w < BLOCK_SIZE; w++)
                cache[s][b].data[w] = 0;
        end
    end
end

logic [1:0] block_index, lru_index;
logic found_invalid;

assign word_offset = PC[3:2];
assign set_index = PC[5:4];
assign pc_tag = PC[31:6];
assign miss = !hit;

// determine if hit
always_comb begin
    hit = 1'b0;
    for(int way = 0; way < BLOCKS_PER_SET; way++) begin
        if (cache[set_index][way].valid && cache[set_index][way].tag == pc_tag) begin
            hit = 1'b1;
            block_index = way;
            break;
        end
    end
end

// logic to determine lru given set index
always_comb begin
    found_invalid = 0;
    // check if there is invalid block
    for(int way = 0; way < BLOCKS_PER_SET; way++) begin
        if (!cache[set_index][way].valid) begin
            lru_index = way;
            found_invalid = 1;
            break;
        end
    end
    
    // if no invalid block then find index for highest lru
    if (!found_invalid) begin
        logic [1:0] max_lru = cache[set_index][0].lru;
        lru_index = 0;
        for(int way = 0; way < BLOCKS_PER_SET; way++) begin
            if(cache[set_index][way].lru > max_lru)
                max_lru = cache[set_index][way].lru;
                lru_index = way;
        end
    end
end

// check if wb is needed and set wb_mem to 1 if needed and 0 if not
always_comb begin
    wb_mem = 0;
    // check if writeing, not a hit, valid bit to write to is 1, and dirty bit is 1 -> when writing form outside
    if(SA_Cache_WE && !hit && cache[set_index][lru_index].valid && cache[set_index][lru_index].dirty)
        wb_mem = 1;
end

// synchronous read based on read enable
always_ff @ (posedge CLK) begin
    if(SA_Cache_rden) begin
        if(hit)
            rd <= cache[set_index][block_index].data[word_offset];
        else
            rd <= 32'h00000013;
    end
end

// update LRU regardless of writing or reading
always_ff @(posedge CLK) begin
    if(hit && (SA_Cache_WE || SA_Cache_rden)) begin
        for(int way = 0; way < BLOCKS_PER_SET; way++) begin
            if (way == block_index)
                cache[set_index][way].lru <= 2'b00;
            else if (cache[set_index][way].lru < 2'b11);
                cache[set_index][way].lru <= cache[set_index][way].lru + 1;
        end
    end
end

// handle cache writing
always_ff @ (posedge CLK) begin
    // check if writing to cache
    if(SA_Cache_WE) begin
        // check if place being written to is in cache
        if(hit) begin
            cache[set_index][block_index].dirty <= 1;
            cache[set_index][block_index].data[word_offset] <= DIN2;
            cache[set_index][lru_index].tag <= pc_tag;
            cache[set_index][lru_index].valid <= 1;
        end
        // if writting but miss
        else begin
            // check if lru has a valid bit
            if (cache[set_index][lru_index].valid) begin
                // check dirty bit
                if (cache[set_index][lru_index].dirty) begin
                    // outputs 4 words to be written back to memory
                    ww0 <= cache[set_index][lru_index].data[0];
                    ww1 <= cache[set_index][lru_index].data[1];
                    ww2 <= cache[set_index][lru_index].data[2];
                    ww3 <= cache[set_index][lru_index].data[3];
                end
                else begin
                    // not dirty so can just write data
                    cache[set_index][lru_index].dirty <= 1;
                    cache[set_index][lru_index].valid <= 1;
                    cache[set_index][lru_index].data[word_offset] <= DIN2;
                    cache[set_index][lru_index].tag <= pc_tag;
                end
            end
            // dont check dirty bit since invalid and write data, mark dirty, and valid
            else begin
                cache[set_index][lru_index].dirty <= 1;
                cache[set_index][lru_index].valid <= 1;
                cache[set_index][lru_index].data[word_offset] <= DIN2;
                cache[set_index][lru_index].tag <= pc_tag;
            end
        end
    end
end

always_ff @ (posedge CLK) begin
    if(update && cache[set_index][lru_index].valid) begin
        cache[set_index][lru_index].data[0] <= rw0;
        cache[set_index][lru_index].data[1] <= rw1;
        cache[set_index][lru_index].data[2] <= rw2;
        cache[set_index][lru_index].data[3] <= rw3;
        cache[set_index][lru_index].valid <= 1;
        cache[set_index][lru_index].tag <= pc_tag;
        if (cache[set_index][lru_index].dirty)begin
            ww0 <= cache[set_index][lru_index].data[0];
            ww1 <= cache[set_index][lru_index].data[1];
            ww2 <= cache[set_index][lru_index].data[2];
            ww3 <= cache[set_index][lru_index].data[3];
            cache[set_index][lru_index].dirty <= 0;
            wb_adr <= {cache[set_index][lru_index].tag, set_index, 4'b0000};
        end
    end
end

endmodule