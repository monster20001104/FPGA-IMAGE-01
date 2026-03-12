module top #(
    parameter       BOARD_MAC       =   48'h00_11_22_33_44_55       ,//开发板MAC地址 00-11-22-33-44-55；
    parameter       BOARD_IP        =   {8'd192,8'd168,8'd1,8'd10}  ,//开发板IP地址 192.168.1.10；
    parameter       DES_MAC         =   48'hff_ff_ff_ff_ff_ff       ,//目的MAC地址 ff_ff_ff_ff_ff_ff；
    parameter       DES_IP          =   {8'd192,8'd168,8'd1,8'd102} ,//目的IP地址 192.168.1.102；
    parameter       BOARD_PORT      =   16'd1234                    ,//开发板的UDP端口号；
    parameter       DES_PORT        =   16'd5678                     //目的端口号；
)(
    input									clk		                ,//系统时钟信号；
    input									rst_n	                ,//系统复位信号，低电平有效；
    //DDR3接口信号；
    inout           [15 : 0]                ddr3_dq                 ,//ddr3 数据；
    inout           [1 : 0]                 ddr3_dqs_n              ,//ddr3 dqs负；
    inout           [1 : 0]                 ddr3_dqs_p              ,//ddr3 dqs正；
    output          [14 : 0]                ddr3_addr               ,//ddr3 地址；
    output          [2 : 0]                 ddr3_ba                 ,//ddr3 banck地址；
    output                                  ddr3_ras_n              ,//ddr3 行选择；
    output                                  ddr3_cas_n              ,//ddr3 列选择；
    output                                  ddr3_we_n               ,//ddr3 读写选择；
    output                                  ddr3_reset_n            ,//ddr3 复位;
    output                                  ddr3_ck_p               ,//ddr3 时钟正;
    output                                  ddr3_ck_n               ,//ddr3 时钟负;
    output                                  ddr3_cke                ,//ddr3 时钟使能;
    output                                  ddr3_cs_n               ,//ddr3 片选;
    output          [1 : 0]                 ddr3_dm                 ,//ddr3_dm;
    output                                  ddr3_odt                ,//ddr3_odt;
    //RGMII以太网接口信号；
    input                                   rgmii_rxc               ,//RGMII接收接口时钟信号；
    input           [3 : 0]                 rgmii_rxd               ,//RGMII接收接口数据信号；
    input                                   rgmii_rx_ctl            ,//RGMII接收接口数据有效指示信号；
    output                                  rgmii_txc               ,//RGMII发送接口时钟输入信号；
    output          [3 : 0]                 rgmii_txd               ,//RGMII发送接口数据输入信号；
    output                                  rgmii_tx_ctl            ,//RGMII发送接口数据输入有效指示信号；
    //DVI输出信号接口
    output                                  tmds_clk_p              ,// TMDS 时钟通道
    output                                  tmds_clk_n              ,
    //output                                  tmds_oen                ,
    output          [2 : 0]                 tmds_data_p             ,// TMDS 数据通道
    output          [2 : 0]                 tmds_data_n     
);
    wire                                    gmii_tx_en              ;
    wire            [7 : 0]                 gmii_txd                ;
    wire                                    gmii_rx_clk             ;
    wire                                    gmii_tx_clk             ;
    wire            [7:0]                   gmii_rxd                ;
    wire                                    gmii_rx_dv              ;
    wire                                    idelay_clk              ;
    wire                                    udp_rx_done             ;
    wire                                    udp_rx_data_vld         ;
    wire            [7 : 0]                 udp_rx_data             ;
    wire            [15 : 0]                udp_rx_data_num         ;

    wire                                    clk_200m                ;
    wire                                    dvi_clk                 ;
    wire                                    dvi_clk_5x              ;
    wire                                    sys_rst_n               ;
    wire                                    ddr3_init_done          ;

    wire                                    wfifo_wren              ;// 原udp_data输出：写使能
    wire            [15 : 0]                wfifo_wdata             ;// 原udp_data输出：16位拼接数据
    wire                                    video_vs                ;
    wire                                    data_req                ;
    wire            [15 : 0]                pixel_data              ;
    wire                                    rfifo_rrst_busy         ;
    wire                                    wfifo_wrst_busy         ;
    wire            [10 : 0]                rfifo_rcount            ;//读FIFO中的数据个数；
    
    //=====================================================
    // 新增：vip中值滤波所需中间信号（衔接udp_data和ddr3_top）
    //=====================================================
    wire                                    vip_pre_vsync           ;// 滤波前-场同步（用udp_rx_done模拟帧结束）
    wire                                    vip_pre_href            ;// 滤波前-行同步（流式传输恒为高）
    wire                                    vip_pre_de              ;// 滤波前-数据有效（=wfifo_wren）
    wire            [15 : 0]                vip_pre_rgb             ;// 滤波前-16位RGB565数据（=wfifo_wdata）
    
    wire                                    vip_post_vsync          ;// 滤波后-场同步（无用，悬空）
    wire                                    vip_post_href           ;// 滤波后-行同步（无用，悬空）
    wire                                    vip_post_de             ;// 滤波后-数据有效（传给DDR写使能）
    wire            [15 : 0]                vip_post_rgb            ;// 滤波后-16位RGB565数据（传给DDR写数据）
    
    //例化锁相环，输出200MHZ时钟，作为以太网和DDR的参考时钟，
    //生成65MHz时钟作为HDMI的参考时钟信号；
    clk_wiz_0 u_clk_wiz_0(
        .clk_out1   ( clk_200m      ),//output clk_out1
        .clk_out2   ( dvi_clk       ),//output clk_out2
        .clk_out3   ( dvi_clk_5x    ),//output clk_out3
        .resetn     ( rst_n         ),//input resetn
        .locked     ( sys_rst_n     ),//output locked
        .clk_in1    ( clk           ) //input clk_in1
    );      

    //例化gmii转RGMII模块。
    rgmii_to_gmii u_rgmii_to_gmii (
        .idelay_clk              ( clk_200m     ),//IDELAY时钟；
        .rst_n                   ( sys_rst_n    ),
        //GMII接口信号
        .gmii_tx_en              ( gmii_tx_en   ),//GMII发送数据使能信号；
        .gmii_txd                ( gmii_txd     ),//GMII发送数据；
        .gmii_rx_clk             ( gmii_rx_clk  ),//GMII接收时钟；
        .gmii_rx_dv              ( gmii_rx_dv   ),//GMII接收数据有效信号；
        .gmii_rxd                ( gmii_rxd     ),//GMII接收数据；
        .gmii_tx_clk             ( gmii_tx_clk  ),//GMII发送时钟；
        //RGMII接口信号；
        .rgmii_rxc               ( rgmii_rxc    ),//RGMII接收时钟；
        .rgmii_rx_ctl            ( rgmii_rx_ctl ),//RGMII接收数据控制信号；
        .rgmii_rxd               ( rgmii_rxd    ),//RGMII接收数据；
        .rgmii_txc               ( rgmii_txc    ),//RGMII发送时钟；
        .rgmii_tx_ctl            ( rgmii_tx_ctl ),//RGMII发送数据控制信号；
        .rgmii_txd               ( rgmii_txd    ) //RGMII发送数据；
    );

    //例化以太网发送和接收模块；
    eth #(
        .BOARD_MAC      ( BOARD_MAC     ),//开发板MAC地址 00-11-22-33-44-55
        .BOARD_IP       ( BOARD_IP      ),//开发板IP地址 192.168.1.10；
        .DES_MAC        ( DES_MAC       ),//目的MAC地址 ff_ff_ff_ff_ff_ff；
        .DES_IP         ( DES_IP        ),//目的IP地址 192.168.1.102；
        .BOARD_PORT     ( BOARD_PORT    ),//开发板的UDP端口号；
        .DES_PORT       ( DES_PORT      ) //目的端口号；
    )
    u_eth (
        //GMII接口；
        .rst_n              ( sys_rst_n         ),
        .gmii_rx_clk        ( gmii_rx_clk       ),
        .gmii_rx_dv         ( gmii_rx_dv        ),
        .gmii_rxd           ( gmii_rxd          ),
        .gmii_tx_clk        ( gmii_tx_clk       ),
        .gmii_tx_en         ( gmii_tx_en        ),
        .gmii_txd           ( gmii_txd          ),
        //用户接口；
        .arp_req            ( 1'b0              ),
        .udp_tx_en          ( 1'b0              ),
        .udp_tx_data        ( 8'd0              ),
        .udp_tx_data_num    ( 0                 ),
        .udp_tx_req         (                   ),
        .udp_rx_done        ( udp_rx_done       ),// 一帧UDP数据接收完成（用于模拟vip的vsync）
        .udp_rx_data        ( udp_rx_data       ),
        .udp_rx_data_num    ( udp_rx_data_num   ),
        .udp_rx_data_vld    ( udp_rx_data_vld   ),
        .tx_rdy             (                   )
    );

    //例化数据拼接模块，将8位数据拼接为16位数据；
    udp_data  u_udp_data (
        .clk        ( gmii_rx_clk       ),
        .rst_n      ( sys_rst_n         ),
        .din        ( udp_rx_data       ),
        .din_vld    ( udp_rx_data_vld   ),
        .dout       ( wfifo_wdata       ),// 输出16位RGB565数据→vip输入
        .dout_vld   ( wfifo_wren        )// 输出数据有效→vip数据有效
    );

wire   wfifo_full;

    //=====================================================
    // 新增：例化中值滤波顶层模块（vip）
    // 时钟：gmii_rx_clk（与udp_data、DDR写时钟同步，避免跨时钟域）
    //=====================================================
    vip u_vip(
        //module clock
        .clk              ( gmii_rx_clk       ),  // 与UDP接收/DDR写时钟一致
        .rst_n            ( sys_rst_n         ),  // 系统复位（低有效）

        // 图像处理前的数据接口（输入：udp_data拼接后的16位数据）
        .pre_frame_vsync  ( vip_pre_vsync     ),  // 场同步：用udp_rx_done模拟（一帧接收完成）
        .pre_frame_href   ( vip_pre_href      ),  // 行同步：流式传输恒为高（UDP连续传一行数据）
        .pre_frame_de     ( vip_pre_de        ),  // 数据有效：=udp_data的dout_vld
        .pre_rgb          ( vip_pre_rgb       ),  // 原始数据：=udp_data的dout（16位RGB565）

        // 图像处理后的数据接口（输出：滤波后的数据→DDR写入）
        .post_frame_vsync ( vip_post_vsync    ),  // 无用，悬空
        .post_frame_href  ( vip_post_href     ),  // 无用，悬空
        .post_frame_de    ( vip_post_de       ),  // 滤波后数据有效→DDR写使能
        .post_rgb         ( vip_post_rgb      )   // 滤波后数据→DDR写数据（8位灰度→16位RGB565）
    );

    // 给vip输入信号赋值（适配UDP流式传输特性）
    assign vip_pre_vsync = udp_rx_done;    // 每接收一帧UDP数据，触发一次场同步
    assign vip_pre_href  = 1'b1;           // UDP是连续流式传输，行同步恒为高
    assign vip_pre_de    = wfifo_wren;     // 仅当udp_data输出有效数据时，vip才处理
    assign vip_pre_rgb   = wfifo_wdata;    // udp_data拼接后的16位RGB565数据

    //例化DDR3顶层模块（修改：写数据/写使能改为vip的输出）
    ddr3_top u_ddr3_top (
        .sys_clk_i          ( clk_200m          ),
        .rst_n              ( sys_rst_n         ),
        .ddr3_init_done     ( ddr3_init_done    ),
        //DDR3接口信号
        .ddr3_addr          ( ddr3_addr         ),
        .ddr3_ba            ( ddr3_ba           ),
        .ddr3_ras_n         ( ddr3_ras_n        ),
        .ddr3_cas_n         ( ddr3_cas_n        ),
        .ddr3_we_n          ( ddr3_we_n         ),
        .ddr3_reset_n       ( ddr3_reset_n      ),
        .ddr3_ck_p          ( ddr3_ck_p         ),
        .ddr3_ck_n          ( ddr3_ck_n         ),
        .ddr3_cke           ( ddr3_cke          ),
        .ddr3_cs_n          ( ddr3_cs_n         ),
        .ddr3_dm            ( ddr3_dm           ),
        .ddr3_odt           ( ddr3_odt          ),
        .ddr3_dq            ( ddr3_dq           ),
        .ddr3_dqs_n         ( ddr3_dqs_n        ),
        .ddr3_dqs_p         ( ddr3_dqs_p        ),
        //复位及突发读写长度设置信号；
        .app_addr_wr_min    ( 29'd0             ),
        .app_addr_wr_max    ( 29'd786432        ),
        .app_wr_bust_len    ( 8'd128            ),
        .app_addr_rd_min    ( 29'd0             ),
        .app_addr_rd_max    ( 29'd786432        ),
        .app_rd_bust_len    ( 8'd128            ),
        .wr_rst             ( ddr3_init_done    ),
        .rd_rst             ( video_vs          ),
        //写数据相关信号；（核心修改：对接vip输出）
        .wfifo_wclk         ( gmii_rx_clk       ),// 时钟不变，与vip保持同步
        .wfifo_wren         ( vip_post_de       ),// 写使能=vip滤波后数据有效
        .wfifo_wdata        ( vip_post_rgb      ),// 写数据=vip滤波后16位数据
        .wfifo_wcount       (                   ),
        .wfifo_full         ( wfifo_full        ),
        .wfifo_wrst_busy    ( wfifo_wrst_busy   ),
        //读数据相关信号（无修改）
        .rfifo_rclk         ( dvi_clk           ),
        .rfifo_rden         ( data_req          ),
        .rfifo_rdata        ( pixel_data        ),
        .rfifo_rcount       ( rfifo_rcount      ),
        .rfifo_empty        (                   ),
        .rfifo_rrst_busy    ( rfifo_rrst_busy   )
    );

    //例化DVI接口驱动模块（无修改）
    dvi_top  u_dvi_top (
        .dvi_clk            ( dvi_clk           ),
        .dvi_clk_5x         ( dvi_clk_5x        ),
        .rst_n              ( sys_rst_n         ),
        .ddr3_init_done     ( ddr3_init_done    ),
        .rfifo_rrst_busy    ( rfifo_rrst_busy   ),
        .pixel_data         ( pixel_data        ),
        .data_req           ( data_req          ),
        .video_vs           ( video_vs          ),
        //HDMI接口信号
        .tmds_clk_p         ( tmds_clk_p        ),
        .tmds_clk_n         ( tmds_clk_n        ),
        //.tmds_oen           ( tmds_oen          ),
        .tmds_data_p        ( tmds_data_p       ),
        .tmds_data_n        ( tmds_data_n       )
    );

endmodule