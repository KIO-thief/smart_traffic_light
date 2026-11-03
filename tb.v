`timescale 1ns / 1ps

module tb_smart_traffic;

// 输入信号
reg clk;
reg rst_n;
reg main_sensor;
reg branch_sensor;
reg emergency_switch;

// 输出信号
wire main_red, main_yellow, main_green;
wire branch_red, branch_yellow, branch_green;
wire [7:0] main_countdown, branch_countdown;
wire emerg_out;

// CLK_FREQ(50) 仅限仿真加速使用
smart_traffic_light #( 
    .CLK_FREQ(50) 
) u_traffic (
    .clk(clk), 
    .rst_n(rst_n),
    .main_sensor(main_sensor), 
    .branch_sensor(branch_sensor),
    .emergency_switch(emergency_switch),     
    .main_red(main_red), 
    .main_yellow(main_yellow), 
    .main_green(main_green),
    .branch_red(branch_red), 
    .branch_yellow(branch_yellow), 
    .branch_green(branch_green),
    .main_countdown(main_countdown), 
    .branch_countdown(branch_countdown),
    .emerg_out(emerg_out)
);

// 产生 50MHz 时钟
initial clk = 0;
always #10 clk = ~clk;

// 生成波形文件
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_smart_traffic);
end

// 看门狗：防止逻辑错误导致仿真卡死
initial begin
    #100_000_000; 
    $display("🚨 ERROR: Simulation TIMEOUT! Check for deadlocks.");
    $finish;
end

// 模拟按键任务
task press_main; begin
    @(posedge clk); main_sensor = 1;
    @(posedge clk); main_sensor = 0;
    repeat(2) @(posedge clk); 
end endtask

task press_branch; begin
    @(posedge clk); branch_sensor = 1;
    @(posedge clk); branch_sensor = 0;
    repeat(2) @(posedge clk);
end endtask

// 测试主流程
initial begin
    rst_n = 0; main_sensor = 0; branch_sensor = 0; emergency_switch = 0;
    #100 rst_n = 1;
    
    // 场景1：进入主干绿灯并稳定
    wait(main_green == 1'b1);
    #100;
    repeat(150) @(posedge clk); 
    
    // 场景2：时间级自适应（绿灯延长）
    $display("Time: %0t | Injecting Main Traffic", $time);
    press_main(); press_main(); press_main(); 

    // 场景3：方向级仲裁
    wait(main_red == 1'b1 && branch_red == 1'b1);
    #100;
    $display("Time: %0t | ALL_RED. Injecting Branch Traffic", $time);
    press_branch(); press_branch(); press_branch();

    // 场景4：应急抢占
    wait(main_green == 1'b1);
    #100;
    $display("Time: %0t | EMERGENCY Triggered", $time);
    emergency_switch = 1; #5000; emergency_switch = 0; 
    
    #5000;
    $display("Time: %0t | Simulation Finished Successfully!", $time);
    $finish;
end

// 状态日志打印
reg [2:0] state_curr, state_prev;
always @(*) begin
    if(!rst_n) state_curr = 3'd7;
    else if(main_green && branch_red) state_curr = 3'd0;
    else if(main_yellow && branch_red) state_curr = 3'd1;
    else if(main_red && branch_green) state_curr = 3'd2;
    else if(main_red && branch_yellow) state_curr = 3'd3;
    else if(main_red && branch_red && emerg_out) state_curr = 3'd5;
    else if(main_red && branch_red) state_curr = 3'd4;
    else state_curr = 3'd7;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) state_prev <= 3'd7;
    else begin
        state_prev <= state_curr;
        if(state_curr != state_prev) begin 
            case(state_curr)
                3'd0: $display("Time: %0t | STATE: MAIN_GREEN", $time);
                3'd1: $display("Time: %0t | STATE: MAIN_YELLOW", $time);
                3'd2: $display("Time: %0t | STATE: BRANCH_GREEN", $time);
                3'd3: $display("Time: %0t | STATE: BRANCH_YELLOW", $time);
                3'd4: $display("Time: %0t | STATE: ALL_RED", $time);
                3'd5: $display("Time: %0t | STATE: EMERGENCY_LOCKED", $time);
                default: $display("Time: %0t | STATE: UNKNOWN(Glitch)", $time);
            endcase
        end
    end
end

endmodule