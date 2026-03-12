module eth #(
    parameter       BOARD_MAC       =   48'h00_11_22_33_44_55       ,//开发板MAC地址 00-11-22-33-44-55；
    parameter       BOARD_IP        =   {8'd192,8'd168,8'd1,8'd10}  ,//开发板IP地址 192.168.1.10；
    parameter       DES_MAC         =   48'hff_ff_ff_ff_ff_ff       ,//目的MAC地址 ff_ff_ff_ff_ff_ff；
    parameter       DES_IP          =   {8'd192,8'd168,8'd1,8'd102} ,//目的IP地址 192.168.1.102；
    parameter       BOARD_PORT      =   16'd1234                    ,//开发板的UDP端口号；
    parameter       DES_PORT        =   16'd5678                    ,//目的端口号；
    parameter       IP_TYPE         =   16'h0800                    ,//16'h0800表示IP协议；
    parameter       ARP_TYPE        =   16'h0806                     //16'h0806表示ARP协议；
)(
    input                               rst_n                       ,//复位信号，低电平有效。
    //GMII接口
    input                               gmii_rx_clk                 ,//GMII接收数据时钟。
    input                               gmii_rx_dv                  ,//GMII输入数据有效信号。
    input           [7 : 0]             gmii_rxd                    ,//GMII输入数据。
    input                               gmii_tx_clk                 ,//GMII发送数据时钟。
    output                              gmii_tx_en                  ,//GMII输出数据有效信号。
    output          [7 : 0]             gmii_txd                    ,//GMII输出数据。
    input                               arp_req                     ,//arp请求数据报发送信号。
    //UDP相关的用户接口；
    input                               udp_tx_en                   ,//UDP发送使能信号。
    input           [7 : 0]             udp_tx_data                 ,//udp需要发送的数据信号，滞后tx_req信号一个时钟；
    input           [15 : 0]            udp_tx_data_num             ,//udp一帧数据需要发送的个数；
    output                              udp_tx_req                  ,//请求输入udp发送数据；
    output                              udp_rx_done                 ,//udp数据报接收完成信号；
    output          [7 : 0]             udp_rx_data                 ,//udp数据接收的数据；
    output          [15 : 0]            udp_rx_data_num             ,//udp接收一帧数据的长度；
    output                              udp_rx_data_vld             ,//udp接收数据有效指示信号；
    output                              tx_rdy                       //以太网发送模块忙闲指示信号；
);
    //以太网发送模块相关信号；
    wire                                eth_tx_start                ;//以太网发送模块开始工作信号;
    wire                                iudp_tx_data_req            ;//发送ICMP或者UDP数据报，请求输入数据段信号；
    wire            [7 : 0]             iudp_tx_data                ;//icmp或者udp需要发送的数据信号;
    wire            [15 : 0]            iudp_tx_byte_num            ;//icmp或者udp发送数据报中数据段的长度;
    wire            [1 : 0]             eth_tx_type                 ;//发送数据报的类型，1表示ARP，2表示ICMP，3表示UDP;
    wire            [1 : 0]             eth_tx_type_r               ;//以太网发送模块正在发送的数据报类型；
    wire                                arp_tx_type                 ;//发送arp数据报的类型，0表示ARP请求，1表示ARP应答;
    wire            [7 : 0]             icmp_tx_type                ;//发送icmp数据报的类型;
    wire            [7 : 0]             icmp_tx_code                ;//发送icmp数据报的代码;
    wire            [15 : 0]            icmp_tx_id                  ;//发送icmp数据报的标识符;
    wire            [15 : 0]            icmp_tx_seq                 ;//发送icmp数据报的序列号;
    wire            [7 : 0]             crc_tx_data                 ;//发送模块需要CRC校验的信号；
    wire                                crc_tx_en                   ;//发送模块CRC校验使能信号；
    wire                                crc_tx_clr                  ;//发送模块CRC校验清零模块；
    wire            [31 : 0]            crc_tx_out                  ;//发送模块的CRC校验结果；
    wire                                icmp_fifo_rd_en             ;//ICMP FIFO的信号;
    wire            [7 : 0]             icmp_fifo_rdata             ;//ICMP FIFO的信号;
    wire                                icmp_fifo_wr_en             ;//ICMP FIFO的信号;
    wire            [7 : 0]             icmp_fifo_wdata             ;//ICMP FIFO的信号;
    
    wire            [1 : 0]             eth_rx_type                 ;//以太网接收模块接收数据报类型。
    wire                                rx_done                     ;//以太网接收模块接收完一帧数据；
    wire                                arp_rx_type                 ;//接收的ARP请求数据报类型；
    wire            [47 : 0]            src_mac                     ;//ARP数据报接收的源MAC地址；
    wire            [31 : 0]            src_ip                      ;//ARP数据报接收的源IP地址；
    wire            [ 7 : 0]            iudp_rx_data                ;//以太网接收的ICMP或者UDP的数据段；
    wire                                iudp_rx_data_vld            ;//以太网接收的数据有效指示信号；
    wire            [15 : 0]            iudp_data_length            ;//以太网接收的数据段长度，单位字节；
    wire            [31 : 0]            icmp_data_checksum          ;//接收的ICMP数据报数据段的校验和。
    wire            [7 : 0]             icmp_rx_type                ;//接收ICMP数据报的类型信号；
    wire            [7 : 0]             icmp_rx_code                ;//接收ICMP数据报的编码信号；
    wire            [15 : 0]            icmp_rx_id                  ;//接收ICMP数据报的标识符信号；
    wire            [15 : 0]            icmp_rx_seq                 ;//接收ICMP数据报的序列号信号；
    wire            [7 : 0]             crc_rx_data                 ;//接收模块需要CRC校验的信号；
    wire                                crc_rx_en                   ;//接收模块CRC校验使能信号；
    wire                                crc_rx_clr                  ;//接收模块CRC校验清零模块；
    wire            [31 : 0]            crc_rx_out                  ;//接收模块的CRC校验结果；
    
    //例化以太网控制模块。
    eth_ctrl  u_eth_ctrl (
        .clk                ( gmii_rx_clk       ),
        .rst_n              ( rst_n             ),
        .arp_req            ( arp_req           ),
        //以太网接收模块连接端口
        .rx_done            ( rx_done           ),
        .eth_rx_type        ( eth_rx_type       ),
        .arp_rx_type        ( arp_rx_type       ),
        .iudp_rx_byte_num   ( iudp_data_length  ),
        .iudp_rx_data       ( iudp_rx_data      ),
        .iudp_rx_data_vld   ( iudp_rx_data_vld  ),
        .icmp_rx_type       ( icmp_rx_type      ),
        .icmp_rx_code       ( icmp_rx_code      ),
        .icmp_rx_id         ( icmp_rx_id        ),
        .icmp_rx_seq        ( icmp_rx_seq       ),
        //以太网发送模块连接端口
        .tx_rdy             ( tx_rdy            ),
        .eth_tx_type_r      ( eth_tx_type_r     ),
        .iudp_tx_data_req   ( iudp_tx_data_req  ),
        
        .eth_tx_start       ( eth_tx_start      ),
        .iudp_tx_data       ( iudp_tx_data      ),
        .iudp_tx_byte_num   ( iudp_tx_byte_num  ),
        .eth_tx_type        ( eth_tx_type       ),
        .arp_tx_type        ( arp_tx_type       ),
        .icmp_tx_type       ( icmp_tx_type      ),
        .icmp_tx_code       ( icmp_tx_code      ),
        .icmp_tx_id         ( icmp_tx_id        ),
        .icmp_tx_seq        ( icmp_tx_seq       ),
        //udp与ICMP用户端口
        .udp_tx_req         ( udp_tx_req        ),
        .udp_tx_en          ( udp_tx_en         ),
        .udp_tx_data        ( udp_tx_data       ),
        .udp_tx_data_num    ( udp_tx_data_num   ),
        .udp_rx_done        ( udp_rx_done       ),
        .udp_rx_data        ( udp_rx_data       ),
        .udp_rx_data_num    ( udp_rx_data_num   ),
        .udp_rx_data_vld    ( udp_rx_data_vld   ),
        .icmp_fifo_wr_en    ( icmp_fifo_wr_en   ),
        .icmp_fifo_wdata    ( icmp_fifo_wdata   ),
        .icmp_fifo_rdata    ( icmp_fifo_rdata   ),
        .icmp_fifo_rd_en    ( icmp_fifo_rd_en   )
    );

    //例化以太网接收模块。
    eth_rx #(
        .BOARD_MAC      ( BOARD_MAC     ),//开发板的MAC地址；
        .BOARD_IP       ( BOARD_IP      ),//开发板的IP地址；
        .BOARD_PORT     ( BOARD_PORT    ) //开发板的UDP端口；
    )
    u_eth_rx (
        .clk                ( gmii_rx_clk       ),
        .rst_n              ( rst_n             ),
        .gmii_rx_dv         ( gmii_rx_dv        ),
        .gmii_rxd           ( gmii_rxd          ),
        .crc_out            ( crc_rx_out        ),
        .crc_data           ( crc_rx_data       ),
        .crc_en             ( crc_rx_en         ),
        .crc_clr            ( crc_rx_clr        ),
        .eth_rx_type        ( eth_rx_type       ),
        .rx_done            ( rx_done           ),
        .iudp_rx_data       ( iudp_rx_data      ),
        .iudp_rx_data_vld   ( iudp_rx_data_vld  ),
        .iudp_data_length   ( iudp_data_length  ),
        .data_checksum      ( icmp_data_checksum),
        .icmp_rx_type       ( icmp_rx_type      ),
        .icmp_rx_code       ( icmp_rx_code      ),
        .icmp_rx_id         ( icmp_rx_id        ),
        .icmp_rx_seq        ( icmp_rx_seq       ),
        .src_mac            ( src_mac           ),
        .src_ip             ( src_ip            ),
        .arp_rx_type        ( arp_rx_type       )
    );

    //例化接收数据时需要的CRC校验模块；
    crc32_d8  u_crc32_d8_rx (
        .clk        ( gmii_tx_clk   ),//时钟信号;
        .rst_n      ( rst_n         ),//复位信号，低电平有效;
        .data       ( crc_rx_data   ),//需要CRC模块校验的数据;
        .crc_en     ( crc_rx_en     ),//CRC开始校验使能;
        .crc_clr    ( crc_rx_clr    ),//CRC数据复位信号;
        .crc_out    ( crc_rx_out    ) //CRC校验模块输出的数据；
    );

    //例化以太网发送模块，包含ARP、ICMP、UDP发送功能。
    eth_tx #(
        .BOARD_MAC  ( BOARD_MAC     ),//开发板MAC地址 00-11-22-33-44-55
        .BOARD_IP   ( BOARD_IP      ),//开发板IP地址 192.168.1.10；
        .DES_MAC    ( DES_MAC       ),//目的MAC地址 ff_ff_ff_ff_ff_ff；
        .DES_IP     ( DES_IP        ),//目的IP地址 192.168.1.102；
        .BOARD_PORT ( BOARD_PORT    ),//开发板的UDP端口号；
        .DES_PORT   ( DES_PORT      ),//目的端口号；
        .IP_TYPE    ( IP_TYPE       ),//16'h0800表示IP协议；
        .ARP_TYPE   ( ARP_TYPE      ) //16'h0806表示ARP协议；
    )
    u_eth_tx (
        .clk                ( gmii_tx_clk       ),//;
        .rst_n              ( rst_n             ),//;
        .eth_tx_start       ( eth_tx_start      ),//;
        .des_mac            ( src_mac           ),//;
        .des_ip             ( src_ip            ),//;
        .iudp_tx_data       ( iudp_tx_data      ),//;
        .iudp_tx_byte_num   ( iudp_tx_byte_num  ),//;
        .eth_tx_type        ( eth_tx_type       ),//;
        .arp_tx_type        ( arp_tx_type       ),//;
        .icmp_tx_type       ( icmp_tx_type      ),//;
        .icmp_tx_code       ( icmp_tx_code      ),//;
        .icmp_tx_id         ( icmp_tx_id        ),//;
        .icmp_tx_seq        ( icmp_tx_seq       ),//;
        .icmp_data_checksum ( icmp_data_checksum),//;
        .eth_tx_type_r      ( eth_tx_type_r     ),//;
        .iudp_tx_data_req   ( iudp_tx_data_req  ),//;
        .crc_out            ( crc_tx_out        ),//;
        .crc_en             ( crc_tx_en         ),//;
        .crc_clr            ( crc_tx_clr        ),//;
        .crc_data           ( crc_tx_data       ),//;
        .gmii_tx_en         ( gmii_tx_en        ),//;
        .gmii_txd           ( gmii_txd          ),//;
        .rdy                ( tx_rdy            ) //;
    );

    //例化发送数据时需要的CRC校验模块；
    crc32_d8  u_crc32_d8_tx (
        .clk        ( gmii_tx_clk   ),//时钟信号;
        .rst_n      ( rst_n         ),//复位信号，低电平有效;
        .data       ( crc_tx_data   ),//需要CRC模块校验的数据;
        .crc_en     ( crc_tx_en     ),//CRC开始校验使能;
        .crc_clr    ( crc_tx_clr    ),//CRC数据复位信号;
        .crc_out    ( crc_tx_out    ) //CRC校验模块输出的数据；
    );

    //例化存储ICMP数据的FIFO，只存储接收的ICMP回显请求数据；
    fifo_generator_0 u_icmp_fifo (
        .clk    ( gmii_rx_clk       ),//input wire clk
        .srst   ( ~rst_n            ),//input wire srst
        .din    ( icmp_fifo_wdata   ),//input wire [7 : 0] din
        .wr_en  ( icmp_fifo_wr_en   ),//input wire wr_en
        .rd_en  ( icmp_fifo_rd_en   ),//input wire rd_en
        .dout   ( icmp_fifo_rdata   ),//output wire [7 : 0] dout
        .full   (                   ),//output wire full
        .empty  (                   ) //output wire empty
    );

endmodule