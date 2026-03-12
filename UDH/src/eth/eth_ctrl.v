module eth_ctrl(
    input                       clk                 ,//时钟。
    input                       rst_n               ,//系统复位信号，低电平有效。
    input                       arp_req             ,//arp请求信号，该信号有效时，向目的IP地址发送一个ARP请求数据报。
    //以太网接收模块相关信号。
    input                       rx_done             ,//接收完成信号。
    input           [1 : 0]     eth_rx_type         ,//接收的以太网数据报类型，1表示ARP，2表示ICMP，3表示UDP。
    input                       arp_rx_type         ,//ARP数据报类型，0表示请求报文。
    input           [15 : 0]    iudp_rx_byte_num    ,//以太网接收的有效字节数 单位:byte。
    input           [7 : 0]     iudp_rx_data        ,//接收的数据段内容，eth_rx_type为2表示ICMP数据段，3表示UDP数据段；
    input                       iudp_rx_data_vld    ,//数据段有效指示信号；
    input           [7 : 0]     icmp_rx_type        ,//ICMP数据报的类型；
    input           [7 : 0]     icmp_rx_code        ,//ICMP数据的代码；
    input           [15 : 0]    icmp_rx_id          ,//ICMP数据包的ID；
    input           [15 : 0]    icmp_rx_seq         ,//ICMP数据报文的标识符；
    //以太网发送模块相关信号。
    input                       tx_rdy              ,//发送模块的忙闲状态，高电平表示空闲；
    output reg                  eth_tx_start        ,
    input           [1 : 0]     eth_tx_type_r       ,//mark:
    input                       iudp_tx_data_req    ,//需要发送数据的请求信号，与需要发送的数据对齐。
    output reg      [7 : 0]     iudp_tx_data        ,//以太网需要发送的数据，延后tx_data_req一个时钟周期；
    output reg      [15 : 0]    iudp_tx_byte_num    ,//ICMP或UDP数据段需要发送的数据。
    output reg      [1 : 0]     eth_tx_type         ,//发送以太网数据报的类型，1表示ARP，2表示ICMP，3表示UDP。
    output reg                  arp_tx_type         ,//ARP数据报文类型，0表示请求数据报，1表示应答数据报文。
    output reg      [7 : 0]     icmp_tx_type        ,//ICMP数据报的类型；
    output reg      [7 : 0]     icmp_tx_code        ,//ICMP数据的代码；
    output reg      [15 : 0]    icmp_tx_id          ,//ICMP数据包的ID；
    output reg      [15 : 0]    icmp_tx_seq         ,//ICMP数据报文的标识符；
    //用户侧接口；
    input                       udp_tx_en           ,//上游模块发送UDP数据,该信号只能拉高一个时钟周期；
    input           [7 : 0]     udp_tx_data         ,//udp发送数据；
    input           [15 : 0]    udp_tx_data_num     ,//udp发送一帧数据的个数，与tx_start对齐；
    output reg                  udp_tx_req          ,//udp发送数据请求；
    
    output reg                  udp_rx_done         ,//udp一帧数据接收完成指示信号；
    output reg      [7 : 0]     udp_rx_data         ,//udp接收数据；
    output reg      [15 : 0]    udp_rx_data_num     ,//udp接收一帧数据的个数；
    output reg                  udp_rx_data_vld     ,//udp接收数据有效指示信号；

    output reg                  icmp_fifo_wr_en     ,//ICMP的FIFO写使能信号；
    output reg      [7 : 0]     icmp_fifo_wdata     ,//ICMP的FIFO写数据信号；
    output reg                  icmp_fifo_rd_en     ,//ICMP的FIFO读使能信号；
    input           [7 : 0]     icmp_fifo_rdata      //ICMP的FIFO读数据信号；
);
    reg                         arp_req_r           ;
    reg                         udp_tx_flag         ;//
    reg                         arp_tx_flag         ;//
    reg                         icmp_tx_flag        ;//
    wire                        icmp_echo_request   ;

    //高电平表示接收的数据报文是ICMP回显请求；
    assign icmp_echo_request = (eth_rx_type == 2'd2) && (icmp_rx_type == 8) && (icmp_rx_code == 0);

    //把UDP发送使能信号暂存，可能当前发送模块处于工作状态；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            udp_tx_flag <= 1'b0;
        end
        else if(udp_tx_en)begin
            udp_tx_flag <= 1'b1;
        end
        else if(eth_tx_start && (&eth_tx_type))begin
            udp_tx_flag <= 1'b0;
        end
    end

    //把arp发送使能信号暂存，可能当前发送模块处于工作状态；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            arp_tx_flag <= 1'b0;
            arp_req_r <= 1'b0;
        end
        //当接受到ARP请求数据包，或者需要发出ARP请求时拉高；
        else if((rx_done && (eth_rx_type == 2'd1) && ~arp_rx_type) || arp_req)begin
            arp_tx_flag <= 1'b1;
            arp_req_r <= arp_req;
        end//当ARP指令发送出去后拉低。
        else if(eth_tx_start && (eth_tx_type == 2'd1))begin
            arp_tx_flag <= 1'b0;
            arp_req_r <= 1'b0;
        end
    end

    //把icmp发送使能信号暂存，可能当前发送模块处于工作状态；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            icmp_tx_flag <= 1'b0;
        end
        //当接受到ICMP回显请求时拉高；
        else if(rx_done && icmp_echo_request)begin
            icmp_tx_flag <= 1'b1;
        end//当ICMP指令发送出去后拉低。
        else if(eth_tx_start && (eth_tx_type == 2'd2))begin
            icmp_tx_flag <= 1'b0;
        end
    end

    //开始发送以太网帧；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            eth_tx_start <= 1'b0;
            eth_tx_type <= 2'd0;
            arp_tx_type <= 1'b0;
            icmp_tx_type <= 8'd0;
            icmp_tx_code <= 8'd0;
            icmp_tx_id <= 16'd0;
            icmp_tx_seq <= 16'd0;
            iudp_tx_byte_num <= 16'd0;
        end
        //接收到ARP的请求数据报时，把开始发送信号拉高；
        else if(arp_tx_flag && tx_rdy)begin
            eth_tx_start <= 1'b1;
            eth_tx_type <= 2'd1;
            arp_tx_type <= arp_req_r ? 1'b0 : 1'b1;//发送ARP应答报文；
        end//当接收到ICMP回显请求时，把开始发送信号拉高；
        else if(icmp_tx_flag && tx_rdy)begin
            eth_tx_start <= 1'b1;
            eth_tx_type <= 2'd2;
            icmp_tx_type <= 8'd0;//发送ICMP回显应答数据报文。
            icmp_tx_code <= 8'd0;
            icmp_tx_id  <= icmp_rx_id;//将回显请求的的ID传回去。
            icmp_tx_seq <= icmp_rx_seq;
            iudp_tx_byte_num <= iudp_rx_byte_num;
        end//当需要发送udp数据时，把开始发送信号拉高；
        else if(udp_tx_flag && tx_rdy)begin
            eth_tx_start <= 1'b1;
            eth_tx_type <= 2'd3;
            iudp_tx_byte_num <= udp_tx_data_num;
        end//如果检测到模块处于空闲状态，则将开始信号拉低。
        else begin
            eth_tx_start <= 1'b0;
        end
    end
    
    //将接收的ICMP数据存入FIFO中。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            icmp_fifo_wr_en <= 1'b0;
            icmp_fifo_wdata <= 8'd0;
        end//如果接收的数据是ICMP数据段的数据，把ICMP的数据存储到FIFO中。
        else if(iudp_rx_data_vld && icmp_echo_request)begin
            icmp_fifo_wr_en <= 1'b1;
            icmp_fifo_wdata <= iudp_rx_data;
        end
        else begin
            icmp_fifo_wr_en <= 1'b0;
        end
    end

    //通过数据请求信号产生从ICMP的FIFO中读取数据或者向用户接口发送UDP数据请求信号；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            udp_tx_req <= 1'b0;
            icmp_fifo_rd_en <= 1'b0;
        end
        else if(iudp_tx_data_req)begin
            if(eth_tx_type_r == 2'd2)begin//如果发送的是ICMP数据报，则从FIFO中读取数据；
                udp_tx_req <= 1'b0;
                icmp_fifo_rd_en <= 1'b1;
            end
            else begin//否则表示发送的UDP数据报，则从外部获取UDP数据。
                udp_tx_req <= 1'b1;
                icmp_fifo_rd_en <= 1'b0;
            end
        end
        else begin
            udp_tx_req <= 1'b0;
            icmp_fifo_rd_en <= 1'b0;
        end
    end

    //将ICMP FIFO或者外部UDP获取的数据发送给以太网发送模块；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            iudp_tx_data <= 8'd0;
        end
        else if(eth_tx_type_r == 2'd2)begin
            iudp_tx_data <= icmp_fifo_rdata;
        end
        else begin
            iudp_tx_data <= udp_tx_data;
        end
    end

    //将接收的UDP数据输出。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            udp_rx_data_vld <= 1'b0;
            udp_rx_data <= 8'd0;
        end//如果接收到UDP数据段信号，将UDP的数据输出。
        else if(iudp_rx_data_vld && eth_rx_type == 2'd3)begin
            udp_rx_data_vld <= 1'b1;
            udp_rx_data <= iudp_rx_data;
        end
        else begin
            udp_rx_data_vld <= 1'b0;
        end
    end

    //一帧UDP数据接收完成。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            udp_rx_done <= 1'b0;
            udp_rx_data_num <= 16'd0;
        end
        else if(&eth_rx_type)begin//如果接收的是UDP数据报；
            udp_rx_done <= rx_done;//将输出完成信号输出；
            udp_rx_data_num <= iudp_rx_byte_num;//把UDP数据长度输出；
        end
    end

endmodule