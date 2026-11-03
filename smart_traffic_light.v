module smart_traffic_light #(
    parameter CLK_FREQ = 50_000_000
) (
    input clk, rst_n,
    input main_sensor, branch_sensor, 
    input emergency_switch,           

    output reg main_red, main_yellow, main_green,
    output reg branch_red, branch_yellow, branch_green,
    output [7:0] main_countdown, branch_countdown, 
    output emerg_out                   
);

//交通灯时间设置
parameter MAIN_BASE_GREEN = 10;
parameter MAIN_MAX_GREEN = 15;
parameter BRANCH_BASE_GREEN = 8;
parameter BRANCH_MAX_GREEN = 12;
parameter YELLOW_TIME = 2;
parameter ALL_RED_TIME = 1;
parameter CAR_THRESHOLD = 2;

localparam [2:0]
S_MAIN_GREEN = 3'd0, S_MAIN_YELLOW = 3'd1,
S_BRANCH_GREEN = 3'd2, S_BRANCH_YELLOW = 3'd3,
S_ALL_RED = 3'd4, S_EMERGENCY = 3'd5;

reg tick_1s;
reg [25:0] tick_cnt;
reg [7:0] timer_sec;
reg [2:0] current_state, next_state;
reg [7:0] main_car_cnt, branch_car_cnt;
reg last_main_was_green;

//打拍
//紧急按键
reg [1:0] emerg_sync;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) emerg_sync <= 2'b00;
    else emerg_sync <= {emerg_sync[0], emergency_switch};
end
wire emerg_stable = emerg_sync[1];

//车流模拟按键
reg [2:0] main_sensor_sync, branch_sensor_sync;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin main_sensor_sync <= 0; branch_sensor_sync <= 0; end 
    else begin
        main_sensor_sync <= {main_sensor_sync[1:0], main_sensor};
        branch_sensor_sync <= {branch_sensor_sync[1:0], branch_sensor};
    end
end
wire main_sensor_pulse = main_sensor_sync[2] & ~main_sensor_sync[1];
wire branch_sensor_pulse = branch_sensor_sync[2] & ~branch_sensor_sync[1];

//1s脉冲发生器
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin tick_cnt <= 0; tick_1s <= 0; end 
    else if(tick_cnt == CLK_FREQ - 1) begin tick_cnt <= 0; tick_1s <= 1; end 
    else begin tick_cnt <= tick_cnt + 1; tick_1s <= 0; end
end

//车流计数器
wire clear_car_cnt = tick_1s && (current_state == S_ALL_RED) && (timer_sec == ALL_RED_TIME - 1);
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin main_car_cnt <= 0; branch_car_cnt <= 0; end
//紧急状态结束清零
    else if (current_state == S_EMERGENCY && next_state == S_ALL_RED) begin
        main_car_cnt <= 8'd0; branch_car_cnt <= 8'd0;
    end
//周期结束清零
    else if(clear_car_cnt) begin main_car_cnt <= 0; branch_car_cnt <= 0; end
//正常计数
    else begin
        if(main_sensor_pulse && (main_car_cnt < 8'hFF)) main_car_cnt <= main_car_cnt + 1'b1;
        if(branch_sensor_pulse && (branch_car_cnt < 8'hFF)) branch_car_cnt <= branch_car_cnt + 1'b1;
    end
end

//车流统计模拟
wire extend_main_green = (current_state == S_MAIN_GREEN) && (main_car_cnt > CAR_THRESHOLD) && (timer_sec < MAIN_MAX_GREEN - 1);
wire extend_branch_green = (current_state == S_BRANCH_GREEN) && (branch_car_cnt > CAR_THRESHOLD) && (timer_sec < BRANCH_MAX_GREEN - 1);

//历史状态记录
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) last_main_was_green <= 0;
    else if(tick_1s) begin
        if(next_state == S_MAIN_GREEN) last_main_was_green <= 1;
        else if(next_state == S_BRANCH_GREEN) last_main_was_green <= 0;
    end
end

//三段式状态机
//寄存现态
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) current_state <= S_ALL_RED; 
    else if(tick_1s) current_state <= next_state;
end
//判断跳转
always @(*) begin
//默认保持现状
next_state = current_state;
//紧急状态+安全过渡
    if (emerg_stable) begin 
        if (current_state == S_MAIN_GREEN || current_state == S_BRANCH_GREEN) next_state = S_MAIN_YELLOW; 
        else if (current_state == S_MAIN_YELLOW || current_state == S_BRANCH_YELLOW) next_state = S_ALL_RED; 
        else next_state = S_EMERGENCY; 
    end else begin
        case(current_state)
//黄绿灯+防饿死
            S_MAIN_GREEN: begin
                if(timer_sec >= MAIN_MAX_GREEN - 1) next_state = S_MAIN_YELLOW;
                else if(timer_sec >= MAIN_BASE_GREEN - 1 && !extend_main_green) next_state = S_MAIN_YELLOW;
            end
            S_MAIN_YELLOW: begin if(timer_sec >= YELLOW_TIME - 1) next_state = S_ALL_RED; end 
            S_BRANCH_GREEN: begin
                if(timer_sec >= BRANCH_MAX_GREEN - 1) next_state = S_BRANCH_YELLOW;
                else if(timer_sec >= BRANCH_BASE_GREEN - 1 && !extend_branch_green) next_state = S_BRANCH_YELLOW;
            end
            S_BRANCH_YELLOW: begin if(timer_sec >= YELLOW_TIME - 1) next_state = S_ALL_RED; end
//全红解除
            S_ALL_RED: begin
                if(timer_sec >= ALL_RED_TIME - 1) begin
                    if(main_car_cnt > branch_car_cnt) next_state = S_MAIN_GREEN;
                    else if(branch_car_cnt > main_car_cnt) next_state = S_BRANCH_GREEN;
                    else next_state = last_main_was_green ? S_BRANCH_GREEN : S_MAIN_GREEN;
                end
            end
//紧急状态解除
            S_EMERGENCY: begin
                if (!emerg_stable) next_state = S_ALL_RED; 
            end
//其他情况全红
            default: next_state = S_ALL_RED;
        endcase
    end
end
//计时
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) timer_sec <= 0;
    else if(tick_1s) begin
        if(next_state != current_state) timer_sec <= 0;
        else timer_sec <= timer_sec + 1;
    end
end
//主干交通灯轮转
always @(*) begin
//默认灭灯
    main_red = 0; main_yellow = 0; main_green = 0;
    branch_red = 0; branch_yellow = 0; branch_green = 0;
    case(current_state)
        S_MAIN_GREEN: begin main_green = 1; branch_red = 1; end
        S_MAIN_YELLOW: begin main_yellow = 1; branch_red = 1; end
        S_BRANCH_GREEN: begin main_red = 1; branch_green = 1; end
        S_BRANCH_YELLOW: begin main_red = 1; branch_yellow = 1; end
        S_ALL_RED, 
        S_EMERGENCY: begin main_red = 1; branch_red = 1; end
//其他情况全红 
        default: begin main_red = 1; branch_red = 1; end
    endcase
end
//双向倒计时
reg [7:0] cd_main, cd_branch;
always @(*) begin
//默认为0
cd_main = 0; cd_branch = 0;
    case(current_state)
//主路绿灯倒计时
        S_MAIN_GREEN: begin
            cd_main = (timer_sec < MAIN_BASE_GREEN) ? (MAIN_BASE_GREEN - timer_sec) : ((MAIN_MAX_GREEN > timer_sec) ? (MAIN_MAX_GREEN - timer_sec) : 0);
            cd_branch = cd_main + YELLOW_TIME + ALL_RED_TIME; // 支干显示红灯等待时间
        end
//主黄
        S_MAIN_YELLOW: begin
            cd_main = (YELLOW_TIME > timer_sec) ? (YELLOW_TIME - timer_sec) : 0;
            cd_branch = cd_main + ALL_RED_TIME;
        end
//干绿
        S_BRANCH_GREEN: begin
            cd_branch = (timer_sec < BRANCH_BASE_GREEN) ? (BRANCH_BASE_GREEN - timer_sec) : ((BRANCH_MAX_GREEN > timer_sec) ? (BRANCH_MAX_GREEN - timer_sec) : 0);
            cd_main = cd_branch + YELLOW_TIME + ALL_RED_TIME; // 主干显示红灯等待时间
        end
//干黄
        S_BRANCH_YELLOW: begin
            cd_branch = (YELLOW_TIME > timer_sec) ? (YELLOW_TIME - timer_sec) : 0;
            cd_main = cd_branch + ALL_RED_TIME;
        end
//全红与紧急状态
        S_ALL_RED: begin
            cd_main = (ALL_RED_TIME > timer_sec) ? (ALL_RED_TIME - timer_sec) : 0;
            cd_branch = cd_main;
        end
        S_EMERGENCY: begin
            cd_main = 0;
            cd_branch = 0;
        end
//默认为0        
        default: begin cd_main = 0; cd_branch = 0; end
    endcase
end
//输出信号
assign main_countdown = cd_main;
assign branch_countdown = cd_branch;
assign emerg_out = (current_state == S_EMERGENCY) ? 1'b1 : 1'b0;

endmodule