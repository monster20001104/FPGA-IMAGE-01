module rgmii_rx #(
    parameter   IDELAY_VALUE = 0  //输入数据IO延时(如果为n,表示延时n*78+600ps);
)(
    input                       idelay_clk      ,//200Mhz时钟，IDELAY时钟
    input                       rst_n           ,//复位信号，低电平有效；
    
    //以太网RGMII接口
    input                       rgmii_rxc       ,//RGMII接收时钟
    input                       rgmii_rx_ctl    ,//RGMII接收数据控制信号
    input       [3:0]           rgmii_rxd       ,//RGMII接收数据    

    //以太网GMII接口
    output                      gmii_rx_clk     ,//GMII接收时钟
    output                      gmii_rx_dv      ,//GMII接收数据有效信号
    output      [7:0]           gmii_rxd         //GMII接收数据   
);
    wire                        rgmii_rxc_bufg  ;//全局时钟缓存
    wire                        rgmii_rxc_bufio ;//全局时钟IO缓存
    wire        [4 : 0]         din             ;//将接收的数据和控制信号进行拼接；
    wire        [4 : 0]         din_delay       ;//将接收到的数据延时2ns。
    wire        [9 : 0]         gmii_data       ;//双沿转单沿的信号；
    wire                        rst             ;//将IDELAYCTRL的空闲信号作为复位信号；

    assign gmii_rx_clk = rgmii_rxc_bufg;//将时钟全局时钟网络驱动CLB等资源。

    ///例化全局时钟资源。
    BUFG BUFG_inst (
        .I  ( rgmii_rxc         ),//1-bit input: Clock input
        .O  ( rgmii_rxc_bufg    ) //1-bit output: Clock output
    );

    //全局时钟IO缓存
    BUFIO BUFIO_inst (
        .I  ( rgmii_rxc         ),//1-bit input: Clock input
        .O  ( rgmii_rxc_bufio   ) //1-bit output: Clock output
    );

    //输入延时控制
    (* IODELAY_GROUP = "rgmii_rx" *) 
    IDELAYCTRL  IDELAYCTRL_inst (
        .RDY    ( rst           ),//1-bit output: Ready output
        .REFCLK ( idelay_clk    ),//1-bit input: Reference clock input
        .RST    ( ~rst_n        ) //1-bit input: Active high reset input
    );

    //将输入控制信号和数据进行拼接，便于后面好用循环进行处理。
    assign din[4 : 0] = {rgmii_rx_ctl,rgmii_rxd};

    //rgmii_rx_ctl和rgmii_rxd输入延时与双沿采样
    generate
        genvar i;
        for(i=0 ; i<5 ; i=i+1)begin : RXDATA_BUS
            //输入延时
            (* IODELAY_GROUP = "rgmii_rx" *) 
            IDELAYE2 #(
                .IDELAY_TYPE        ( "FIXED"           ),//FIXED,VARIABLE,VAR_LOAD,VAR_LOAD_PIPE
                .IDELAY_VALUE       ( IDELAY_VALUE      ),//Input delay tap setting (0-31)    
                .REFCLK_FREQUENCY   ( 200.0             ) //IDELAYCTRL clock input frequency in MHz
            )
            u_delay_rxd (
                .CNTVALUEOUT        (                   ),//5-bit output: Counter value output
                .DATAOUT            ( din_delay[i]      ),//1-bit output: Delayed data output
                .C                  ( 1'b0              ),//1-bit input: Clock input
                .CE                 ( 1'b0              ),//1-bit input: enable increment/decrement
                .CINVCTRL           ( 1'b0              ),//1-bit input: Dynamic clock inversion
                .CNTVALUEIN         ( 5'b0              ),//5-bit input: Counter value input
                .DATAIN             ( 1'b0              ),//1-bit input: Internal delay data input
                .IDATAIN            ( din[i]            ),//1-bit input: Data input from the I/O
                .INC                ( 1'b0              ),//1-bit input: Inc/Decrement tap delay
                .LD                 ( 1'b0              ),//1-bit input: Load IDELAY_VALUE input
                .LDPIPEEN           ( 1'b0              ),//1-bit input: Enable PIPELINE register 
                .REGRST             ( ~rst              ) //1-bit input: Active-high reset tap-delay
            );
            
            //输入双沿采样寄存器
            IDDR #(
                .DDR_CLK_EDGE   ( "SAME_EDGE_PIPELINED" ),//"OPPOSITE_EDGE", "SAME_EDGE" or "SAME_EDGE_PIPELINED" 
                .INIT_Q1        ( 1'b0                  ),//Initial value of Q1: 1'b0 or 1'b1
                .INIT_Q2        ( 1'b0                  ),//Initial value of Q2: 1'b0 or 1'b1
                .SRTYPE         ( "SYNC"                ) //Set/Reset type: "SYNC" or "ASYNC" 
            ) 
            u_iddr_rxd (
                .Q1             ( gmii_data[i]          ),//1-bit output for positive edge of clock
                .Q2             ( gmii_data[5 + i]      ),//1-bit output for negative edge of clock
                .C              ( rgmii_rxc_bufio       ),//1-bit clock input rgmii_rxc_bufio
                .CE             ( 1'b1                  ),//1-bit clock enable input
                .D              ( din_delay[i]          ),//1-bit DDR data input
                .R              ( ~rst_n                ),//1-bit reset
                .S              ( 1'b0                  ) //1-bit set
            );
        end
    endgenerate

    //通过拼接生成数据信号和数据有效指示信号。
    assign gmii_rxd = {gmii_data[8:5],gmii_data[3:0]};
    assign gmii_rx_dv = gmii_data[4] & gmii_data[9];//只有当上升沿和下降沿采集到的控制信号均为高电平时，数据才有效。
    
endmodule