`define HDMI_768P
module video_driver (
    input           	        clk	            ,//系统时钟信号；
    input           	        rst_n  	        ,//系统复位信号，低电平有效；
    input                       ddr3_init_done  ,//DDR3初始化完成；
    input                       rfifo_rrst_busy ,//读FIFO的复位状态指示信号；
	
    output  reg     	        video_hs	    ,//行同步信号;
    output  reg     	        video_vs	    ,//场同步信号;
    output  reg     	        video_de	    ,//数据使能;
    output  reg [23:0]          video_rgb	    ,//RGB888颜色数据;

    output	reg			        data_req 	    ,//像素申请信号；
    input   	[23:0]          pixel_data	    ,//像素点数据;
    output  reg	[10:0]          pixel_xpos	    ,//像素点横坐标;
    output  reg	[10:0]          pixel_ypos       //像素点纵坐标;
);
    `ifdef HDMI_720P//1280*720 分辨率时序参数;60HZ刷新率对应时钟频率74.25MHZ
        localparam  H_SYNC      =   11'd40      ;//行同步;
        localparam  H_BACK      =   11'd220     ;//行显示后沿;
        localparam  H_DISP      =   11'd1280    ;//行有效数据;
        localparam  H_FRONT     =   11'd110     ;//行显示前沿;

        localparam  V_SYNC      =   11'd5       ;//场同步;
        localparam  V_BACK      =   11'd20      ;//场显示后沿;
        localparam  V_DISP      =   11'd720     ;//场有效数据;
        localparam  V_FRONT     =   11'd5       ;//场显示前沿;
    `elsif HDMI_768P//1024*768,60HZ分辨率时序参数;对应时钟频率65MHz；
        localparam  H_SYNC      =  12'd136      ;//行同步;
        localparam  H_BACK      =  12'd160      ;//行显示后沿;
        localparam  H_DISP      =  12'd1024     ;//行有效数据;
        localparam  H_FRONT     =  12'd24       ;//行显示前沿;

        localparam  V_SYNC      =  12'd6        ;//场同步;
        localparam  V_BACK      =  12'd29       ;//场显示后沿;
        localparam  V_DISP      =  12'd768      ;//场有效数据;
        localparam  V_FRONT     =  12'd3        ;//场显示前沿;
    `elsif HDMI1080P//1920*1080分辨率时序参数，60HZ刷新率对应时钟频率148.5MHZ
        localparam  H_SYNC      =  12'd44       ;//行同步;
        localparam  H_BACK      =  12'd148      ;//行显示后沿;
        localparam  H_DISP      =  12'd1920     ;//行有效数据;
        localparam  H_FRONT     =  12'd88       ;//行显示前沿;

        localparam  V_SYNC      =  12'd5        ;//场同步;
        localparam  V_BACK      =  12'd36       ;//场显示后沿;
        localparam  V_DISP      =  12'd1080     ;//场有效数据;
        localparam  V_FRONT     =  12'd4        ;//场显示前沿;
    `else//1024*600分辨率时序参数;
        localparam  H_SYNC      =  12'd20       ;//行同步;
        localparam  H_BACK      =  12'd140      ;//行显示后沿;
        localparam  H_DISP      =  12'd1024     ;//行有效数据;
        localparam  H_FRONT     =  12'd160      ;//行显示前沿;

        localparam  V_SYNC      =  12'd3        ;//场同步;
        localparam  V_BACK      =  12'd20       ;//场显示后沿;
        localparam  V_DISP      =  12'd600      ;//场有效数据;
        localparam  V_FRONT     =  12'd12       ;//场显示前沿;
    `endif

    localparam  SHOW_H_B    =   H_SYNC + H_BACK;//LCD图像行起点;
    localparam  SHOW_V_B    =   V_SYNC + V_BACK;//LCD图像场起点;
    localparam  SHOW_H_E    =   H_SYNC + H_BACK + H_DISP;//LCD图像行结束;
    localparam  SHOW_V_E    =   V_SYNC + V_BACK + V_DISP;//LCD图像场结束;
    localparam  H_TOTAL     =   H_SYNC + H_BACK + H_DISP + H_FRONT ;//行扫描周期;
    localparam  V_TOTAL     =   V_SYNC + V_BACK + V_DISP + V_FRONT;//场扫描周期;
    localparam  H_TOTAL_W   =   clogb2(H_TOTAL - 1);
    localparam  V_TOTAL_W   =   clogb2(V_TOTAL - 1);

    reg       	                video_en    ;
    reg  [H_TOTAL_W - 1 : 0]    cnt_h       ;
    reg  [V_TOTAL_W - 1 : 0]    cnt_v       ;
    
    //自动计算位宽函数
    function integer clogb2(input integer depth);begin
        if(depth == 0)
            clogb2 = 1;
        else if(depth != 0)
            for(clogb2=0 ; depth>0 ; clogb2=clogb2+1)
                depth=depth >> 1;
        end
    endfunction

    //行计数器对像素时钟计数;
    always@(posedge clk)begin
        if(~rst_n)
            cnt_h <= {{H_TOTAL_W}{1'b0}};
        else if(~ddr3_init_done)//DDR3复位未完成时清零；
            cnt_h <= {{H_TOTAL_W}{1'b0}};
        else if(cnt_h >= H_TOTAL - 1)
            cnt_h <= {{H_TOTAL_W}{1'b0}};
        else
            cnt_h <= cnt_h + 1'b1;
    end

    //场计数器对行计数;
    always@(posedge clk)begin
        if(~rst_n)
            cnt_v <= {{V_TOTAL_W}{1'b0}};
        else if(~ddr3_init_done)//DDR3复位未完成时清零；
            cnt_v <= {{V_TOTAL_W}{1'b0}};
        else if(cnt_h == H_TOTAL - 1'b1) begin
            if(cnt_v >= V_TOTAL - 1'b1)
                cnt_v <= {{V_TOTAL_W}{1'b0}};
            else
                cnt_v <= cnt_v + 1'b1;
        end
    end

    //请求像素点颜色数据输入，在产生行场同步信号前两个时钟向上游产生请求信号；
    always@(posedge clk)begin
        if(~rst_n)//初始值为0;
            data_req <= 1'b0;
        else if((cnt_h >= SHOW_H_B - 1) && (cnt_h < SHOW_H_E - 1) && (cnt_v >= SHOW_V_B - 1) && (cnt_v < SHOW_V_E - 1))
            data_req <= 1'b1;
        else
            data_req <= 1'b0;
    end

    //生产X轴坐标值，与req信号对齐；
    always@(posedge clk)begin
        if(~rst_n)//初始值为0;
            pixel_xpos <= 11'd0;
        else if((cnt_h >= SHOW_H_B - 1) && (cnt_h < SHOW_H_E - 1))
            pixel_xpos <= cnt_h + 1 - SHOW_H_B;
        else 
            pixel_xpos <= 11'd0;
    end

    //生产y轴坐标值，与req信号对齐；
    always@(posedge clk)begin
        if(~rst_n)//初始值为0;
            pixel_ypos <= 11'd0;
        else if((cnt_v >= SHOW_V_B - 1) && (cnt_v < SHOW_V_E - 1))
            pixel_ypos <= cnt_v + 1 - SHOW_V_B;
        else 
            pixel_ypos <= 11'd0;
    end


    always@(posedge clk)begin
        if(~rst_n)begin//初始值为0;
            video_hs <= 1'b0;
            video_vs <= 1'b0;
            video_en <= 1'b0;
            video_de <= 1'b0;
            video_rgb <= 24'd0;
        end
        else begin
            video_en <= data_req;
            video_de <= video_en;
            video_hs <= (cnt_h >= H_SYNC);//行同步信号赋值;
            video_vs <= (cnt_v >= V_SYNC);//场同步信号赋值;
            video_rgb <= video_en ? pixel_data : 24'd0;//RGB888数据输出;
        end
    end

endmodule