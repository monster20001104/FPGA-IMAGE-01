module  dvi_top(
    input                   dvi_clk         ,//DVI时钟信号，1024*768分辨率时为65MHz。
    input                   dvi_clk_5x      ,//DVI的5倍参考时钟信号。
    input                   rst_n           ,//复位信号，低电平有效。
    input                   ddr3_init_done  ,//DDR3初始化完成；
    input                   rfifo_rrst_busy ,//读FIFO的复位状态指示信号；

    output                  video_vs        ,
    output                  data_req        ,
    input   [15 : 0]        pixel_data      ,//请求输入的像素数据信号，与像素请求信号对齐；
    //DVI输出信号接口
    output                  tmds_clk_p      ,// TMDS 时钟通道
    output                  tmds_clk_n      ,
    //output                  tmds_oen        ,
    output [2 : 0]          tmds_data_p     ,// TMDS 数据通道
    output [2 : 0]          tmds_data_n      
    
);
    wire  [23 : 0]          pixel_data_w    ;
    wire                    video_hs        ;
    wire                    video_vs        ;
    wire                    video_de        ;
    wire  [23 : 0]          video_rgb       ;

    ///将输入的16位像素数据拼接成24位像素输入数据；
    assign pixel_data_w = {pixel_data[15 : 11],3'd0,pixel_data[10:5],2'd0,pixel_data[4:0],3'd0};

    //例化视频显示驱动模块
    video_driver  u_video_driver(
        .clk            ( dvi_clk       ),//系统时钟信号；
        .rst_n          ( rst_n         ),//复位信号，低电平有效；
        .ddr3_init_done ( ddr3_init_done),
        .rfifo_rrst_busy( rfifo_rrst_busy),
        .video_hs       ( video_hs      ),//行同步信号;
        .video_vs       ( video_vs      ),//场同步信号;
        .video_de       ( video_de      ),//数据使能;
        .video_rgb      ( video_rgb     ),//RGB888颜色数据;
        .data_req		( data_req      ),//像素申请信号；
        .pixel_xpos     (               ),//像素点数据;
        .pixel_ypos     (               ),//像素点横坐标;
        .pixel_data     ( pixel_data_w  ) //像素点纵坐标;
    );

    //例化HDMI驱动模块
    dvi_transmitter u_dvi_transmitter(
        .clk           ( dvi_clk    ),//系统时钟信号，
        .clk_5x        ( dvi_clk_5x ),//频率为系统时钟5倍的时钟信号；
        .rst_n         ( rst_n      ),//复位，低电平有效；
        .video_din     ( video_rgb  ),//RGB888视频输入信号；
        .video_hsync   ( video_hs   ),//行同步信号；
        .video_vsync   ( video_vs   ),//场同步信号；
        .video_de      ( video_de   ),//像素使能信号；
        .tmds_clk_p    ( tmds_clk_p ),//TMDS时钟通道;
        .tmds_clk_n    ( tmds_clk_n ),
        .tmds_data_p   ( tmds_data_p),//TMDS数据通道;
        .tmds_data_n   ( tmds_data_n)//, 
        //.tmds_oen      ( tmds_oen   ) //TMDS输出使能;
    );

endmodule 