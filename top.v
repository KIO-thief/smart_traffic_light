module top #(
    parameter CLK_FREQ = 50_000_000
)(
    input  clk,  
    input  [3:0] key,          
    input  emerg_sw,     
    
    output led_m_red, led_m_yellow, led_m_green,
    output led_b_red, led_b_yellow, led_b_green,
    output led_emerg,    
    
    output tm_clk,       
    inout tm_dio        
);

localparam TEST_MODE = 0; //正常模式

wire [7:0] main_cd, branch_cd;
wire emerg_flag;

assign led_emerg = emerg_flag;

//例化按键消抖
wire rst_stable, main_stable, branch_stable;
debounce db_rst (
    .clk(clk),
    .rst_n(1'b1), 
    .btn_in(key[0]),
    .btn_out(rst_stable)
    );
wire rst_n = rst_stable; 

debounce db_main (
    .clk(clk), 
    .rst_n(rst_n), 
    .btn_in(key[1]), 
    .btn_out(main_stable)
);
debounce db_branch (
    .clk(clk), 
    .rst_n(rst_n), 
    .btn_in(key[2]), 
    .btn_out(branch_stable)
);

//例化状态机
smart_traffic_light #( 
    .CLK_FREQ(50_000_000)
) u_traffic (
    .clk(clk), 
    .rst_n(rst_n),
    .main_sensor(main_stable), .branch_sensor(branch_stable),
    .emergency_switch(emerg_sw),     
    .main_red(led_m_red), .main_yellow(led_m_yellow), .main_green(led_m_green),
    .branch_red(led_b_red), .branch_yellow(led_b_yellow), .branch_green(led_b_green),
    .main_countdown(main_cd), .branch_countdown(branch_cd),
    .emerg_out(emerg_flag)
    );

wire [7:0] final_main_cd = (TEST_MODE == 1'b1) ? 8'd12 : main_cd;
wire [7:0] final_branch_cd = (TEST_MODE == 1'b1) ? 8'd34 : branch_cd;

wire [3:0] num0 = final_main_cd / 10;
wire [3:0] num1 = final_main_cd % 10;
wire [3:0] num2 = final_branch_cd / 10;
wire [3:0] num3 = final_branch_cd % 10;

//例化TM1637数码管驱动
tm1637_driver u_display (
    .clk(clk), 
    .rst_n(rst_n),
    .num0(num0), 
    .num1(num1), 
    .num2(num2), 
    .num3(num3), 
    .tm_clk(tm_clk), 
    .tm_dio(tm_dio)
);

endmodule