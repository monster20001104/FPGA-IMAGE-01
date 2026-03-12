module  dvi_top_new(
    input                   dvi_clk         ,//DVI时钟信号，1024*768分辨率时为65MHz
    input                   dvi_clk_5x      ,//DVI的5倍参考时钟信号
    input                   rst_n           ,//复位信号，低电平有效
    input                   ddr3_init_done  ,//DDR3初始化完成
    input                   rfifo_rrst_busy ,//读FIFO的复位状态指示信号

    output                  video_vs        ,//原生场同步，反馈给DDR3做读侧复位
    output                  data_req        ,//请求数据的使能信号
    input   [15 : 0]        pixel_data      ,//请求输入的像素数据信号，与请求对齐

    //DVI输出信号接口
    output                  tmds_clk_p      ,// TMDS 时钟通道
    output                  tmds_clk_n      ,
    output [2 : 0]          tmds_data_p     ,// TMDS 数据通道
    output [2 : 0]          tmds_data_n      
);

    // video_driver 产生的原生视频流信号
    wire  [23 : 0]          pixel_data_w    ;
    wire                    video_hs        ;
    wire                    video_vs        ;
    wire                    video_de        ;
    wire  [23 : 0]          video_rgb       ;
    
    // VIP 模块相关的流水线信号
    wire  [15 : 0]          pre_rgb         ;
    wire                    post_frame_vsync;
    wire                    post_frame_href ;
    wire                    post_frame_de   ;
    wire  [15 : 0]          post_rgb        ;
    wire  [23 : 0]          post_rgb_24bit  ;

    // 将请求回来的16位RGB565零扩展为24位RGB888，送入时序发生器
    assign pixel_data_w = {pixel_data[15:11], 3'd0, pixel_data[10:5], 2'd0, pixel_data[4:0], 3'd0};

    // 例化视频显示驱动模块
    video_driver  u_video_driver(
        .clk            ( dvi_clk           ),
        .rst_n          ( rst_n             ),
        .ddr3_init_done ( ddr3_init_done    ),
        .rfifo_rrst_busy( rfifo_rrst_busy   ),
        .video_hs       ( video_hs          ),
        .video_vs       ( video_vs          ),// 输出原生场同步
        .video_de       ( video_de          ),
        .video_rgb      ( video_rgb         ),
        .data_req		( data_req          ),
        .pixel_xpos     (                   ),
        .pixel_ypos     (                   ),
        .pixel_data     ( pixel_data_w      ) 
    );

    // 截取原生24位RGB888的高位，恢复出16位RGB565供VIP处理
    assign pre_rgb = {video_rgb[23:19], video_rgb[15:10], video_rgb[7:3]};

    // 例化VIP图像处理模块 (中值滤波等)
    vip u_vip(
        .clk                ( dvi_clk           ), 
        .rst_n              ( rst_n             ), 

        // 图像处理前的数据接口
        .pre_frame_vsync    ( video_vs          ),
        .pre_frame_href     ( video_hs          ),
        .pre_frame_de       ( video_de          ),
        .pre_rgb            ( pre_rgb           ),

        // 图像处理后的数据接口 (存在流水线Latency)
        .post_frame_vsync   ( post_frame_vsync  ),
        .post_frame_href    ( post_frame_href   ),
        .post_frame_de      ( post_frame_de     ),
        .post_rgb           ( post_rgb          ) 
    );

    // 将VIP处理后的16位RGB565再次重组为24位RGB888，供DVI发送端编码
    assign post_rgb_24bit = {post_rgb[15:11], 3'd0, post_rgb[10:5], 2'd0, post_rgb[4:0], 3'd0};

    // 例化HDMI驱动发送模块
    dvi_transmitter u_dvi_transmitter(
        .clk           ( dvi_clk          ),
        .clk_5x        ( dvi_clk_5x       ),
        .rst_n         ( rst_n            ),
        .video_din     ( post_rgb_24bit   ),// 接入滤波后的像素数据
        .video_hsync   ( post_frame_href  ),// 接入延迟对齐后的行同步
        .video_vsync   ( post_frame_vsync ),// 接入延迟对齐后的场同步
        .video_de      ( post_frame_de    ),// 接入延迟对齐后的数据使能
        .tmds_clk_p    ( tmds_clk_p       ),
        .tmds_clk_n    ( tmds_clk_n       ),
        .tmds_data_p   ( tmds_data_p      ),
        .tmds_data_n   ( tmds_data_n      ) 
    );

endmodule