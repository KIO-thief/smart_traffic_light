module debounce #(
    parameter CLK_FREQ = 50_000_000, 
    parameter DELAY_MS = 20
)(
    input  clk,
    input  rst_n,
    input  btn_in,
    output reg btn_out
);

localparam CNT_MAX = CLK_FREQ * DELAY_MS / 1000;

reg [1:0] btn_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) btn_sync <= 2'b11;
    else        btn_sync <= {btn_sync[0], btn_in};
end

reg [31:0] cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt     <= 32'd0;
        btn_out <= 1'b1;
    end 
    else if (btn_sync[1] != btn_out) begin
        if (cnt >= CNT_MAX - 1) begin
            cnt     <= 32'd0;
            btn_out <= btn_sync[1];
        end else begin
            cnt     <= cnt + 1'b1;
        end
    end 
    else begin
        cnt <= 32'd0;
    end
end

endmodule