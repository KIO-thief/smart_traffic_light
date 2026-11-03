module tm1637_driver (
input clk, rst_n,
input [3:0] num0, num1, num2, num3,
output reg tm_clk,
inout tm_dio
);
// 2kHz 慢速,同步
reg [15:0] clk_cnt;
wire tick = (clk_cnt == 16'd24999); 
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) clk_cnt <= 0;
    else if(tick) clk_cnt <= 0;
    else clk_cnt <= clk_cnt + 1;
end

reg dio_dir;
reg dio_out;
assign tm_dio = dio_dir ? dio_out : 1'bz;

localparam S_IDLE=4'd0, S_START=4'd1, S_TX=4'd2, S_ACK=4'd3, S_STOP=4'd4, S_WAIT=4'd5;
reg [3:0] state;
reg [2:0] step, bit_idx;
reg [2:0] frame_idx; 
reg [1:0] byte_sub_idx; 
reg [7:0] tx_byte;
reg [7:0] temp;
reg [15:0] wait_cnt;

function [7:0] get_code; 
input [3:0] n;
reg [7:0] temp;
    begin case(n)
        4'd0: temp = 8'hC0; 4'd1: temp = 8'hF9; 4'd2: temp = 8'hA4; 4'd3: temp = 8'hB0;
        4'd4: temp = 8'h99; 4'd5: temp = 8'h92; 4'd6: temp = 8'h82; 4'd7: temp = 8'hF8;
        4'd8: temp = 8'h80; 4'd9: temp = 8'h90; default: temp = 8'hFF;
    endcase
    get_code = ~temp;
    end
endfunction

always @(*) begin
    case(frame_idx)
        3'd0: tx_byte = 8'h44;
        3'd1: tx_byte = (byte_sub_idx == 0) ? 8'hC0 : get_code(num0);
        3'd2: tx_byte = (byte_sub_idx == 0) ? 8'hC1 : (get_code(num1) & 8'h7F);
        3'd3: tx_byte = (byte_sub_idx == 0) ? 8'hC2 : get_code(num2);
        3'd4: tx_byte = (byte_sub_idx == 0) ? 8'hC3 : get_code(num3);
        3'd5: tx_byte = 8'h8F;
        default: tx_byte = 8'h44;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= S_IDLE; step <= 0; bit_idx <= 0; 
        frame_idx <= 0; byte_sub_idx <= 0;
        tm_clk <= 1; dio_dir <= 1; dio_out <= 1; wait_cnt <= 0;
    end
    else if(tick) begin
        case(state)
            S_IDLE: begin
                tm_clk <= 1; dio_dir <= 1; dio_out <= 1; step <= 0; bit_idx <= 0;
                byte_sub_idx <= 0;
                state <= S_START;
            end
            S_START: case(step)
                0: begin dio_out <= 1; tm_clk <= 1; step <= 1; end
                1: begin dio_out <= 0; step <= 2; end
                2: begin tm_clk <= 0; step <= 0; state <= S_TX; end
            endcase
            S_TX: case(step)
                0: begin tm_clk <= 0; dio_out <= tx_byte[bit_idx]; step <= 1; end
                1: begin tm_clk <= 1; step <= 2; end
                2: begin
                    if(bit_idx == 7) begin bit_idx <= 0; state <= S_ACK; step <= 0; end
                    else begin bit_idx <= bit_idx + 1; step <= 0; end
                end
            endcase
            S_ACK: case(step)
                0: begin tm_clk <= 0; dio_dir <= 0; step <= 1; end
                1: begin tm_clk <= 1; step <= 2; end
                2: begin
                    tm_clk <= 0; dio_dir <= 1; step <= 0;
                    if (frame_idx == 3'd0 || frame_idx == 3'd5) begin
                        state <= S_STOP;
                    end else begin
                        if (byte_sub_idx == 1'b0) begin
                            byte_sub_idx <= 1'b1;
                            state <= S_TX;
                        end else begin
                            state <= S_STOP; 
                        end
                    end
                end
            endcase
            S_STOP: case(step)
                0: begin tm_clk <= 0; dio_out <= 0; step <= 1; end
                1: begin tm_clk <= 1; step <= 2; end
                2: begin dio_out <= 1; step <= 3; end
                3: begin
                    step <= 0;
                    state <= S_WAIT; 
                    wait_cnt <= 0;
                end
            endcase
            S_WAIT: begin
                if (wait_cnt >= 16'd50) begin 
                    if (frame_idx == 3'd5) begin
                        frame_idx <= 3'd0; 
                    end else begin
                        frame_idx <= frame_idx + 1'b1; 
                    end
                    state <= S_IDLE;
                end else begin
                    wait_cnt <= wait_cnt + 1'b1;
                end
            end
        endcase
    end
end

endmodule