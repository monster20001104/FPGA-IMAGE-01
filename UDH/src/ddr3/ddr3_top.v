module ddr3_top #(
    parameter   PINGPANG_EN             =       1'b0            ,//乒乓操作是否使能；
    parameter   USE_ADDR_W              =       29              ,//用户需要写入数据的位宽；
    parameter   USE_BUST_LEN_W          =       8               ,//用户侧读写数据突发长度的位宽；
    parameter   USE_DATA_W              =       16              ,//用户侧读写数据的位宽；
    parameter   DDR_ADDR_W              =       29              ,//MIG IP读写数据地址位宽；
    parameter   DDR_DATA_W              =       128              //MIG IP读写数据的位宽；
)(
    input                                       sys_clk_i       ,//MIG IP核输入时钟，200MHz；
    input                                       rst_n           ,//复位,低有效；
    //DDR3 IO接口；
    inout       [15 : 0]                        ddr3_dq         ,//ddr3 数据；
    inout       [1 : 0]                         ddr3_dqs_n      ,//ddr3 dqs负；
    inout       [1 : 0]                         ddr3_dqs_p      ,//ddr3 dqs正；
    output      [14 : 0]                        ddr3_addr       ,//ddr3 地址；
    output      [2 : 0]                         ddr3_ba         ,//ddr3 banck地址；
    output                                      ddr3_ras_n      ,//ddr3 行选择；
    output                                      ddr3_cas_n      ,//ddr3 列选择；
    output                                      ddr3_we_n       ,//ddr3 读写选择；
    output                                      ddr3_reset_n    ,//ddr3 复位;
    output                                      ddr3_ck_p       ,//ddr3 时钟正;
    output                                      ddr3_ck_n       ,//ddr3 时钟负;
    output                                      ddr3_cke        ,//ddr3 时钟使能;
    output                                      ddr3_cs_n       ,//ddr3 片选;
    output      [1 : 0]                         ddr3_dm         ,//ddr3_dm;
    output                                      ddr3_odt        ,//ddr3_odt;
    //DDR3接口信号；
    input       [DDR_ADDR_W - 1 : 0]            app_addr_wr_min ,//读ddr3的起始地址;
    input       [DDR_ADDR_W - 1 : 0]            app_addr_wr_max ,//读ddr3的结束地址;
    input       [USE_BUST_LEN_W - 1 : 0]        app_wr_bust_len ,//从ddr3中读数据时的突发长度;
    input       [DDR_ADDR_W - 1 : 0]            app_addr_rd_min ,//读ddr3的起始地址;
    input       [DDR_ADDR_W - 1 : 0]            app_addr_rd_max ,//读ddr3的结束地址;
    input       [USE_BUST_LEN_W - 1 : 0]        app_rd_bust_len ,//从ddr3中读数据时的突发长度;
    input                                       wr_rst          ,//写复位信号，上升沿有效，持续时间必须大于ui_clk的周期；
    input                                       rd_rst          ,//读复位信号，下降沿有效，持续时间必须大于ui_clk周期；
    //写FIFO用户侧接口信号；
    input                                       wfifo_wclk      ,//写FIFO写时钟信号;
    input                                       wfifo_wren      ,//写FIFO写使能信号；
    input       [USE_DATA_W - 1 : 0]            wfifo_wdata     ,//写FIFO写数据信号；
    output      [USE_BUST_LEN_W + 3 : 0]        wfifo_wcount    ,//写FIFO中的数据个数；
    output                                      wfifo_full      ,//写FIFO满指示信号；
    output                                      wfifo_wrst_busy ,//写FIFO复位完成指示信号，低电平表示复位完成；
    //读FIFO读侧信号；
    input                                       rfifo_rclk      ,//读FIFO读时钟;
    input                                       rfifo_rden      ,//读FIFO读使能信号；
    output      [USE_DATA_W - 1 : 0]            rfifo_rdata     ,//读FIFO读数据；
    output      [USE_BUST_LEN_W + 3 : 0]        rfifo_rcount    ,//读FIFO中的数据个数；
    output                                      rfifo_empty     ,//读FIFO空指示信号；
    output                                      rfifo_rrst_busy ,//读FIFO复位状态指示信号，高电平表示处于复位过程中。

    output                                      ddr3_init_done   //ddr3初始化完成信号;
);
    wire                                        ui_clk              ;//MIG IP输出的用户时钟信号，100MHz；
    wire                                        ui_clk_sync_rst     ;//MIG IP输出的同步复位信号，高电平有效；
    //写FIFO读侧信号；
    wire                                        wfifo_wr_rst        ;//高电平有效；
    wire                                        wfifo_empty         ;//写FIFO的空指示信号；
    wire                                        wfifo_rd_en         ;//写FIFO的读使能信号；
    wire                                        wfifo_rd_rst_busy   ;//写FIFO的复位状态指示信号，高电平表示FIFO处于复位状态；
    wire        [DDR_DATA_W - 1 : 0]            wfifo_rdata         ;//写FIFO的读数据，与读使能信号对齐；
    wire        [USE_BUST_LEN_W : 0]            wfifo_rcount        ;//写FIFO中数据个数；
    //读FIFO写侧信号；
    wire                                        rfifo_rd_rst        ;//高电平有效；
    wire                                        rfifo_full          ;//读FIFO的满指示信号；
    wire                                        rfifo_wr_en         ;//读FIFO的写使能信号；
    wire        [DDR_DATA_W - 1 : 0]            rfifo_wdata         ;//读FIFO的写数据；
    wire                                        rfifo_wrst_busy     ;//读FIFO的复位指示信号，高电平表示FIFO处于复位状态；
    wire        [USE_BUST_LEN_W : 0]            rfifo_wcount        ;//读FIFO中的数据个数；
    //MIG IP用户侧信号；
    wire                                        app_en              ;//命令有效信号；
    wire        [2 : 0]                         app_cmd             ;//命令信号，1表示读命令，0表示写命令；
    wire        [DDR_ADDR_W - 1 : 0]            app_addr            ;//突发读写首地址信号；
    wire                                        app_wdf_wren        ;//写数据使能信号；
    wire                                        app_wdf_end         ;//突发读写最后一个数据指示信号，高电平有效；
    wire        [DDR_DATA_W - 1 : 0]            app_wdf_data        ;//写数据；
    wire                                        app_rdy             ;//接收命令应答信号，高电平有效；
    wire                                        app_wdf_rdy         ;//接收数据应答信号，高电平有效；
    wire        [DDR_DATA_W - 1 : 0]            app_rd_data         ;//读数据；
    wire                                        app_rd_data_valid   ;//读数据指示信号；

    //例化写FIFO IP；
    wrfifo u_wrfifo (
        .rst            ( wfifo_wr_rst      ),//input wire rst;
        .wr_clk         ( wfifo_wclk        ),//input wire wr_clk;
        .rd_clk         ( ui_clk            ),//input wire rd_clk;
        .din            ( wfifo_wdata       ),//input wire [15 : 0] din;
        .wr_en          ( wfifo_wren        ),//input wire wr_en;
        .rd_en          ( wfifo_rd_en       ),//input wire rd_en;
        .dout           ( wfifo_rdata       ),//output wire [127 : 0] dout;
        .full           ( wfifo_full        ),//output wire full;
        .empty          ( wfifo_empty       ),//output wire empty;
        .rd_data_count  ( wfifo_rcount      ),//output wire [8 : 0] rd_data_count;
        .wr_data_count  ( wfifo_wcount      ),//output wire [11 : 0] wr_data_count;
        .wr_rst_busy    ( wfifo_wrst_busy   ),//output wire wr_rst_busy;
        .rd_rst_busy    ( wfifo_rd_rst_busy ) //output wire rd_rst_busy;
    );

    //
    rdfifo u_rdfifo (
        .rst            ( rfifo_rd_rst      ),//input wire rst;
        .wr_clk         ( ui_clk            ),//input wire wr_clk;
        .rd_clk         ( rfifo_rclk        ),//input wire rd_clk;
        .din            ( rfifo_wdata       ),//input wire [127 : 0] din;
        .wr_en          ( rfifo_wr_en       ),//input wire wr_en;
        .rd_en          ( rfifo_rden        ),//input wire rd_en;
        .dout           ( rfifo_rdata       ),//output wire [15 : 0] dout;
        .full           ( rfifo_full        ),//output wire full;
        .empty          ( rfifo_empty       ),//output wire empty;
        .rd_data_count  ( rfifo_rcount      ),//output wire [11 : 0] rd_data_count;
        .wr_data_count  ( rfifo_wcount      ),//output wire [8 : 0] wr_data_count;
        .wr_rst_busy    ( rfifo_wrst_busy   ),//output wire wr_rst_busy;
        .rd_rst_busy    ( rfifo_rrst_busy   ) //output wire rd_rst_busy;
    );

    //例化DDR3读写控制模块；
    ddr3_rw #(
        .PINGPANG_EN            ( PINGPANG_EN       ),//乒乓操作是否使能；
        .USE_ADDR_W             ( USE_ADDR_W        ),//用户需要写入数据的位宽；
        .USE_BUST_LEN_W         ( USE_BUST_LEN_W    ),//用户侧读写数据突发长度的位宽；
        .USE_DATA_W             ( USE_DATA_W        ),//用户侧读写数据的位宽；
        .DDR_ADDR_W             ( DDR_ADDR_W        ),//MIG IP读写数据地址位宽；
        .DDR_DATA_W             ( DDR_DATA_W        ) //MIG IP读写数据的位宽；
    )
    u_ddr3_rw (
        //MIG IP用户侧相关信号；
        .ui_clk                 ( ui_clk            ),//；
        .ui_clk_sync_rst        ( ui_clk_sync_rst   ),//；
        .init_calib_complete    ( ddr3_init_done    ),//；
        .app_rdy                ( app_rdy           ),
        .app_wdf_rdy            ( app_wdf_rdy       ),
        .app_rd_data            ( app_rd_data       ),
        .app_rd_data_valid      ( app_rd_data_valid ),
        .app_en                 ( app_en            ),
        .app_cmd                ( app_cmd           ),
        .app_addr               ( app_addr          ),
        .app_wdf_wren           ( app_wdf_wren      ),
        .app_wdf_end            ( app_wdf_end       ),
        .app_wdf_data           ( app_wdf_data      ),
        //用户设置接口
        .app_addr_wr_min        ( app_addr_wr_min   ),
        .app_addr_wr_max        ( app_addr_wr_max   ),
        .app_wr_bust_len        ( app_wr_bust_len   ),
        .app_addr_rd_min        ( app_addr_rd_min   ),
        .app_addr_rd_max        ( app_addr_rd_max   ),
        .app_rd_bust_len        ( app_rd_bust_len   ),
        .wr_rst                 ( wr_rst            ),
        .rd_rst                 ( rd_rst            ),
        //写FIFO读侧信号
        .wfifo_wr_rst           ( wfifo_wr_rst      ),
        .wfifo_empty            ( wfifo_empty       ),
        .wfifo_rd_rst_busy      ( wfifo_rd_rst_busy ),
        .wfifo_rd_en            ( wfifo_rd_en       ),
        .wfifo_rdata            ( wfifo_rdata       ),
        .wfifo_rdata_count      ( wfifo_rcount      ),
        //读FIFO写侧信号
        .rfifo_rd_rst           ( rfifo_rd_rst      ),
        .rfifo_full             ( rfifo_full        ),
        .rfifo_wr_rst_busy      ( rfifo_wrst_busy   ),
        .rfifo_wdata_count      ( rfifo_wcount      ),
        .rfifo_wr_en            ( rfifo_wr_en       ),
        .rfifo_wdata            ( rfifo_wdata       )
    );

    //例化MIG IP
    mig_7series_0 u_mig_7series_0 (
        // Memory interface ports
        .ddr3_addr              ( ddr3_addr         ),//output [14:0]  ddr3_addr
        .ddr3_ba                ( ddr3_ba           ),//output [2:0]   ddr3_ba
        .ddr3_cas_n             ( ddr3_cas_n        ),//output         ddr3_cas_n
        .ddr3_ck_n              ( ddr3_ck_n         ),//output [0:0]   ddr3_ck_n
        .ddr3_ck_p              ( ddr3_ck_p         ),//output [0:0]   ddr3_ck_p
        .ddr3_cke               ( ddr3_cke          ),//output [0:0]   ddr3_cke
        .ddr3_ras_n             ( ddr3_ras_n        ),//output		   ddr3_ras_n
        .ddr3_reset_n           ( ddr3_reset_n      ),//output		   ddr3_reset_n
        .ddr3_we_n              ( ddr3_we_n         ),//output		   ddr3_we_n
        .ddr3_dq                ( ddr3_dq           ),//inout [15:0]   ddr3_dq
        .ddr3_dqs_n             ( ddr3_dqs_n        ),//inout [1:0]	   ddr3_dqs_n
        .ddr3_dqs_p             ( ddr3_dqs_p        ),//inout [1:0]	   ddr3_dqs_p
        .init_calib_complete    ( ddr3_init_done    ),//output		   init_calib_complete
        .ddr3_cs_n              ( ddr3_cs_n         ),//output [0:0]   ddr3_cs_n
        .ddr3_dm                ( ddr3_dm           ),//output [1:0]   ddr3_dm
        .ddr3_odt               ( ddr3_odt          ),//output [0:0]   ddr3_odt
        // Application interface ports
        .app_addr               ( app_addr          ),//input [28:0]   app_addr
        .app_cmd                ( app_cmd           ),//input [2:0]	   app_cmd
        .app_en                 ( app_en            ),//input		   app_en
        .app_wdf_data           ( app_wdf_data      ),//input [127:0]  app_wdf_data
        .app_wdf_end            ( app_wdf_end       ),//input		   app_wdf_end
        .app_wdf_wren           ( app_wdf_wren      ),//input		   app_wdf_wren
        .app_rd_data            ( app_rd_data       ),//output [127:0] app_rd_data
        .app_rd_data_end        (                   ),//output         app_rd_data_end
        .app_rd_data_valid      ( app_rd_data_valid ),//output         app_rd_data_valid
        .app_rdy                ( app_rdy           ),//output         app_rdy
        .app_wdf_rdy            ( app_wdf_rdy       ),//output         app_wdf_rdy
        .app_sr_req             ( 0                 ),//input          app_sr_req
        .app_ref_req            ( 0                 ),//input          app_ref_req
        .app_zq_req             ( 0                 ),//input          app_zq_req
        .app_sr_active          (                   ),//output         app_sr_active
        .app_ref_ack            (                   ),//output         app_ref_ack
        .app_zq_ack             (                   ),//output         app_zq_ack
        .ui_clk                 ( ui_clk            ),//output         ui_clk
        .ui_clk_sync_rst        ( ui_clk_sync_rst   ),//output         ui_clk_sync_rst
        .app_wdf_mask           ( 16'd0             ),//input [15:0]   app_wdf_mask
        // System Clock Ports
        .sys_clk_i              ( sys_clk_i         ),//系统输入200MHz时钟作为MIG参考和工作时钟；
        .sys_rst                ( rst_n             ) //input sys_rst
    );
    
endmodule