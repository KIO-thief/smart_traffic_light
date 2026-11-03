module clk_div #(
    parameter CLK_FREQ = 50_000_000
)(
    input clk, rst_n,
    output reg tick_1s
);

reg [25:0] tick_cnt;


endmodule