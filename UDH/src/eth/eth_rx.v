//以太网接收模块
module eth_rx #(
    parameter       BOARD_MAC   =   48'h00_11_22_33_44_55       ,//开发板MAC地址 00-11-22-33-44-55;
    parameter       BOARD_IP    =   {8'd192,8'd168,8'd1,8'd10}  ,//开发板IP地址 192.168.1.10;
    parameter       BOARD_PORT  =   16'd1234                     //开发板的UDP端口地址。
)(
    input                           clk                         ,//时钟信号;
    input                           rst_n                       ,//复位信号，低电平有效;
    input                           gmii_rx_dv                  ,//GMII输入数据有效信号
    input           [7 : 0]         gmii_rxd                    ,//GMII输入数据

    input           [31 : 0]        crc_out                     ,//CRC校验数据;
    output  reg     [7 : 0]         crc_data                    ,//需要CRC模块校验的数据;
    output  reg                     crc_en                      ,//CRC开始校验使能
    output  reg                     crc_clr                     ,//CRC数据复位信号 

    output  reg     [1 : 0]         eth_rx_type                 ,//接收以太网协议类型，1：ARP，2：ICMP，3：UDP。
    output  reg                     rx_done                     ,//以太网单包数据接收完成信号
    output  reg     [ 7 : 0]        iudp_rx_data                ,//以太网接收的数据。
    output  reg                     iudp_rx_data_vld            ,//以太网接收的数据，有效指示信号。
    output  reg     [15 : 0]        iudp_data_length            ,//以太网接收的有效数据字节数 单位:byte 
    output  reg     [31 : 0]        data_checksum               ,//ICMP数据段的校验和。
    output  reg     [7 : 0]         icmp_rx_type                ,//ICMP数据报的类型；
    output  reg     [7 : 0]         icmp_rx_code                ,//ICMP数据的代码；
    output  reg     [15 : 0]        icmp_rx_id                  ,//ICMP数据包的ID；
    output  reg     [15 : 0]        icmp_rx_seq                 ,//ICMP数据报文的标识符；
    output  reg     [47 : 0]        src_mac                     ,//ARP接收的源MAC地址；
    output  reg     [31 : 0]        src_ip                      ,//ARP接收的源IP地址；
    output  reg                     arp_rx_type                  //ARP数据报类型，0表示请求报文。
);
    localparam      IDLE        =   8'b0000_0001                ;//初始状态，检测前导码。
    localparam      ETH_HEAD    =   8'b0000_0010                ;//接收以太网帧头。
    localparam      IP_HEAD     =   8'b0000_0100                ;//接收IP帧头。
    localparam      IUDP_HEAD   =   8'b0000_1000                ;//接收ICMP或者UDP帧头。
    localparam      IUDP_DATA   =   8'b0001_0000                ;//接收ICMP或者UDP数据。
    localparam      ARP_DATA    =   8'b0010_0000                ;//接收ARP数据。
    localparam      CRC         =   8'b0100_0000                ;//接收CRC校验码。
    localparam      RX_END      =   8'b1000_0000                ;//接收一帧数据结束。
    //以太网类型定义
    localparam      IP_TPYE     =   16'h0800                    ;//以太网帧类型 IP。
    localparam      ARP_TPYE    =   16'h0806                    ;//以太网帧类型 ARP。
    localparam      ICMP_TYPE   =   8'd01                       ;//ICMP协议类型。
    localparam      UDP_TYPE    =   8'd17                       ;//UDP协议类型。
    
    reg                             start                       ;//检测到前导码和SFD信号后的开始接收数据信号。
    reg                             error_flag                  ;//检测到接收数据包不是发给该开发板或者接收到的不是ARP、ICMP、UDP数据包时拉高。
    reg             [7 : 0]	        state_n                     ;//状态机次态。
    reg             [7 : 0]	        state_c                     ;//状态机现态。
    reg             [15 : 0]        cnt                         ;//计数器，辅助状态机的跳转。
    reg             [15 : 0]        cnt_num                     ;//计数器的状态机每个状态下接收数据的个数。
    reg             [5 : 0]         ip_head_byte_num            ;//IP首部数据的字节数。
    reg             [15 : 0]        ip_total_length             ;//IP报文总长度。
    reg             [15 : 0]        des_ip                      ;//目的IP地址。
    reg             [7 : 0]         gmii_rxd_r      [6 : 0]     ;//接收信号的移位寄存器；
    reg             [6 : 0]         gmii_rx_dv_r                ;
    reg             [23 : 0]        des_crc                     ;//接收的CRC校验数值；
    reg             [47 : 0]        des_mac                     ;
    reg             [15 : 0]        opcode                      ;
    reg             [47 : 0]        src_mac_t                   ;
    reg             [31 : 0]        src_ip_t                    ;
    reg             [31 : 0]        reply_checksum_add          ;

    wire       		                add_cnt                     ;
    wire       		                end_cnt                     ;
    
    //The first section: synchronous timing always module, formatted to describe the transfer of the secondary register to the live register ?
    always@(posedge clk)begin
        if(!rst_n)begin
            state_c <= IDLE;
        end
        else begin
            state_c <= state_n;
        end
    end
    
    //The second paragraph: The combinational logic always module describes the state transition condition judgment.
    always@(*)begin
        case(state_c)
            IDLE:begin
                if(start)begin//检测到前导码和SFD后跳转到接收以太网帧头数据的状态。
                    state_n = ETH_HEAD;
                end
                else begin
                    state_n = state_c;
                end
            end
            ETH_HEAD:begin
                if(error_flag)begin//在接收以太网帧头过程中检测到错误。
                    state_n = RX_END;
                end
                else if(end_cnt)begin//接收完以太网帧头数据，且没有出现错误。
                    if(eth_rx_type == 2'd1)//如果该数据报是ARP类型，则跳转到ARP接收数据状态；
                        state_n = ARP_DATA;
                    else//否则跳转到接收IP报头的状态；
                        state_n = IP_HEAD;
                end
                else begin
                    state_n = state_c;
                end
            end
            IP_HEAD:begin
                if(error_flag)begin//在接收IP帧头过程中检测到错误。
                    state_n = RX_END;
                end
                else if(end_cnt)begin//接收完以IP帧头数据，且没有出现错误。
                    state_n = IUDP_HEAD;//跳转到接收ICMP或UDP报头状态；
                end
                else begin
                    state_n = state_c;
                end
            end
            IUDP_HEAD:begin
                if(end_cnt)begin//接收完以ICMP帧头或UDP帧头数据，则继续接收ICMP数据或UDP数据。
                    state_n = IUDP_DATA;
                end
                else begin
                    state_n = state_c;
                end
            end
            IUDP_DATA:begin
                if(end_cnt)begin//接收完ICMP数据或UDP数据，跳转到CRC校验状态。
                    state_n = CRC;
                end
                else begin
                    state_n = state_c;
                end
            end
            ARP_DATA:begin
                if(error_flag)begin//接收数据出现错误。
                    state_n = RX_END;
                end
                else if(end_cnt)begin//接收完所有数据。
                    state_n = CRC;
                end
                else begin
                    state_n = state_c;
                end
            end
            CRC:begin
                if(end_cnt)begin//接收完CRC校验数据。
                    state_n = RX_END;
                end
                else begin
                    state_n = state_c;
                end
            end
            RX_END:begin
                if(~gmii_rx_dv)begin//检测到数据线上数据无效。
                    state_n = IDLE;
                end
                else begin
                    state_n = state_c;
                end
            end
            default:begin
                state_n = IDLE;
            end
        endcase
    end

    //将输入数据保存6个时钟周期，用于检测前导码和SFD。
    //注意后文的state_c与gmii_rxd_r[0]对齐。
    always@(posedge clk)begin
        gmii_rxd_r[6] <= gmii_rxd_r[5];
        gmii_rxd_r[5] <= gmii_rxd_r[4];
        gmii_rxd_r[4] <= gmii_rxd_r[3];
        gmii_rxd_r[3] <= gmii_rxd_r[2];
        gmii_rxd_r[2] <= gmii_rxd_r[1];
        gmii_rxd_r[1] <= gmii_rxd_r[0];
        gmii_rxd_r[0] <= gmii_rxd;
        gmii_rx_dv_r <= {gmii_rx_dv_r[5 : 0],gmii_rx_dv};
    end

    //在状态机处于空闲状态下，检测到连续7个8'h55后又检测到一个8'hd5后表示检测到帧头，此时将介绍数据的开始信号拉高，其余时间保持为低电平。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            start <= 1'b0;
        end
        else if(state_c == IDLE)begin
            start <= ({gmii_rx_dv_r,gmii_rx_dv} == 8'hFF) && ({gmii_rxd,gmii_rxd_r[0],gmii_rxd_r[1],gmii_rxd_r[2],gmii_rxd_r[3],gmii_rxd_r[4],gmii_rxd_r[5],gmii_rxd_r[6]} == 64'hD5_55_55_55_55_55_55_55);
        end
    end
    
    //计数器，状态机在不同状态需要接收的数据个数不一样，使用一个可变进制的计数器。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//
            cnt <= 0;
        end
        else if(add_cnt)begin
            if(end_cnt)
                cnt <= 0;
            else
                cnt <= cnt + 1;
        end
        else begin//如果加一条件无效，计数器必须清零。
            cnt <= 0;
        end
    end
    //当状态机不在空闲状态或接收数据结束阶段时计数，计数到该状态需要接收数据个数时清零。
    assign add_cnt = (state_c != IDLE) && (state_c != RX_END) && gmii_rx_dv_r[0];
    assign end_cnt = add_cnt && cnt == cnt_num - 1;

    //状态机在不同状态，需要接收不同的数据个数，在接收以太网帧头时，需要接收14byte数据。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为20;
            cnt_num <= 16'd20;
        end
        else begin
            case(state_c)
                ETH_HEAD : cnt_num <= 16'd14;//以太网帧头长度位14字节。
                IP_HEAD  : cnt_num <= ip_head_byte_num;//IP帧头为20字节数据。
                IUDP_HEAD : cnt_num <= 16'd8;//UDP和ICMP帧头为8字节数据。
                IUDP_DATA : cnt_num <= iudp_data_length;//UDP数据段需要根据数据长度进行变化。
                ARP_DATA  : cnt_num <= 16'd46;//ARP数据段46字节。
                CRC      : cnt_num <= 16'd4;//CRC校验为4字节数据。
                default: cnt_num <= 16'd20;
            endcase
        end
    end

    //接收目的MAC地址，需要判断这个包是不是发给开发板的，目的MAC地址是不是开发板的MAC地址或广播地址。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            des_mac <= 48'd0;
        end
        else if((state_c == ETH_HEAD) && add_cnt && cnt < 16'd6)begin
            des_mac <= {des_mac[39:0],gmii_rxd_r[0]};
        end
    end

    //判断接收的数据是否正确，以此来生成错误指示信号，判断状态机跳转。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            error_flag <= 1'b0;
        end
        else if(add_cnt)begin
            case(state_c)
                ETH_HEAD : begin
                    if(cnt == 6)//判断接收的数据是不是发送给开发板或者广播数据。
                        error_flag <= ((des_mac != BOARD_MAC) && (des_mac != 48'HFF_FF_FF_FF_FF_FF));
                    else if(cnt == 12)//接收的数据报不是IP协议且不是ARP协议。
                        error_flag <= ({gmii_rxd_r[0],gmii_rxd} != IP_TPYE) && ({gmii_rxd_r[0],gmii_rxd} != ARP_TPYE);
                end
                IP_HEAD : begin
                    if(cnt == 9)//如果当前接收的数据不是UDP协议，且不是ICMP协议；
                        error_flag <= (gmii_rxd_r[0] != UDP_TYPE) && (gmii_rxd_r[0] != ICMP_TYPE);
                    else if(cnt == 16'd18)//判断目的IP地址是否为开发板的IP地址。
                        error_flag <= ({des_ip,gmii_rxd_r[0],gmii_rxd} != BOARD_IP);
                end
                ARP_DATA : begin
                    if(cnt == 27)begin//判断接收的目的IP地址是否正确，操作码是否为ARP的请求或应答指令。
                        error_flag <= ((opcode != 16'd1) && (opcode != 16'd2)) || ({des_ip,gmii_rxd_r[1],gmii_rxd_r[0]} != BOARD_IP);
                    end
                end
                IUDP_DATA : begin
                    if((cnt == 3) && (eth_rx_type == 2'd3))begin//UDP的目的端口地址不等于开发板的目的端口地址。
                        error_flag <= ({gmii_rxd_r[1],gmii_rxd_r[0]} != BOARD_PORT);
                    end
                end
                default: error_flag <= 1'b0;
            endcase
        end
        else begin
            error_flag <= 1'b0;
        end
    end

    //根据接收的数据判断该数据报的类型。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            eth_rx_type <= 2'd0;
        end//接收的协议是ARP协议；
        else if(state_c == ETH_HEAD && add_cnt && cnt == 12)begin
            if({gmii_rxd_r[0],gmii_rxd} == ARP_TPYE)begin
                eth_rx_type <= 1;
            end
            else begin
                eth_rx_type <= 0;
            end
        end
        else if(state_c == IP_HEAD && add_cnt && cnt == 9)begin
            if(gmii_rxd_r[0] == UDP_TYPE)//接收的数据包是UDP协议；
                eth_rx_type <= 3;
            else if(gmii_rxd_r[0] == ICMP_TYPE)//接收的协议是ICMP协议；
                eth_rx_type <= 2;
        end
    end
    
    //接收IP首部和ARP数据段的数据。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            ip_head_byte_num <= 6'd20;
            ip_total_length <= 16'd28;
            des_ip <= 16'd0;
            iudp_data_length <= 16'd0;
            opcode <= 16'd0;//ARP的OP编码。
            src_mac_t <= 48'd0;//ARP传输的源MAC地址；
            src_ip_t <= 32'd0;//ARP传输的源IP地址；
        end
        else if(state_c == IP_HEAD && add_cnt)begin
            case(cnt)
                16'd0 : ip_head_byte_num <= {gmii_rxd_r[0][3:0],2'd0};//接收IP首部的字节个数。
                16'd3 : ip_total_length <= {gmii_rxd_r[1],gmii_rxd_r[0]};//接收IP报文总长度的低八位数据。
                16'd4 : iudp_data_length <= ip_total_length - ip_head_byte_num - 8;//计算UDP报文数据段的长度，UDP帧头为8字节数据。
                16'd17: des_ip <= {gmii_rxd_r[1],gmii_rxd_r[0]};//接收目的IP地址。
                default: ;
            endcase
        end
        else if(state_c == ARP_DATA && add_cnt)begin
            case(cnt)
                16'd7 : opcode <= {gmii_rxd_r[1],gmii_rxd_r[0]};//操作码;
                16'd13 : src_mac_t <= {gmii_rxd_r[5],gmii_rxd_r[4],gmii_rxd_r[3],gmii_rxd_r[2],gmii_rxd_r[1],gmii_rxd_r[0]};//源MAC地址;
                16'd17 : src_ip_t <= {gmii_rxd_r[3],gmii_rxd_r[2],gmii_rxd_r[1],gmii_rxd_r[0]};//源IP地址;
                16'd25 : des_ip <= {gmii_rxd_r[1],gmii_rxd_r[0]};//接收目的IP地址高16位。
                default: ;
            endcase
        end
    end
    
    //接收ICMP首部相关数据，UDP首部数据不需要保存。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            icmp_rx_type <= 8'd0;//ICMP类型；
            icmp_rx_code <= 8'd0;//ICMP代码；
            icmp_rx_id <= 16'd0;//ICMP标识符
            icmp_rx_seq <= 16'd0;//ICMP请求；
        end
        else if(state_c == IUDP_HEAD && add_cnt)begin
            if(eth_rx_type == 2'd2)//如果是ICMP协议。
                case(cnt)
                    16'd0 : icmp_rx_type <= gmii_rxd_r[0];//接收ICMP报文类型。
                    16'd1 : icmp_rx_code <= gmii_rxd_r[0];//接收ICMP报文代码。
                    16'd5 : icmp_rx_id <= {gmii_rxd_r[1],gmii_rxd_r[0]};//接收ICMP的ID。
                    16'd7 : icmp_rx_seq <= {gmii_rxd_r[1],gmii_rxd_r[0]};//接收ICMP报文的序列号。
                    default: ;
                endcase
        end
    end

    //接收ICMP或者UDP的数据段，并输出使能信号。
    always@(posedge clk)begin
        iudp_rx_data <= (state_c == IUDP_DATA) ? gmii_rxd_r[0] : iudp_rx_data;//在接收UDP数据阶段时，接收数据。
        iudp_rx_data_vld <= (state_c == IUDP_DATA);//在接收数据阶段时，将数据输出。
    end
    
    //生产CRC校验相关的数据和控制信号。
    always@(posedge clk)begin
        crc_data <= gmii_rxd_r[0];//将移位寄存器最低位存储的数据作为CRC输入模块的数据。
        crc_clr <= (state_c == IDLE);//当状态机处于空闲状态时，清除CRC校验模块计算。
        crc_en <= (state_c != IDLE) && (state_c != RX_END) && (state_c != CRC);//CRC校验使能信号。
    end

    //接收PC端发送来的CRC数据。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            des_crc <= 24'hff_ff_ff;
        end
        else if(add_cnt && state_c == CRC)begin//先接收的是低位数据；
            des_crc <= {gmii_rxd_r[0],des_crc[23:8]};
        end
    end

    //计算接收到的ICMP数据段校验和。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            reply_checksum_add <= 32'd0;
        end
        else if(state_c == RX_END)begin//累加器清零。
            reply_checksum_add <= 32'd0;
        end
        else if(state_c == IUDP_DATA && add_cnt && eth_rx_type == 2'd2)begin
            if(end_cnt && iudp_data_length[0])begin//如果计数器计数结束且数据个数为奇数个(最低位为1)，那么直接将当前数据与累加器相加。
                reply_checksum_add <= reply_checksum_add + {8'd0,gmii_rxd_r[0]};
            end
            else if(cnt[0])//计数器计数到奇数时，将前后两字节数据拼接相加。
                reply_checksum_add <= reply_checksum_add + {gmii_rxd_r[1],gmii_rxd_r[0]};
        end
    end

    //生成相应的输出数据。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            rx_done <= 1'b0;//接收一帧数据完成信号，高电平有效；
            src_mac <= 48'd0;//ARP接收的源MAC地址；
            src_ip <= 32'd0;//ARP接收的源IP地址；
            arp_rx_type <= 1'b0;
            data_checksum <= 32'd0;//ICMP数据段校验和；
        end//如果CRC校验成功，把UDP协议接收完成信号拉高，把接收到UDP数据个数和数据段的校验和输出。
        else if(state_c == CRC && end_cnt && ({gmii_rxd_r[0],des_crc[23:0]} == crc_out))begin//CRC校验无误。
            if(eth_rx_type == 2'd1)begin//如果接收的是ARP协议；
                src_mac <= src_mac_t;//将接收的源MAC地址输出；
                src_ip <= src_ip_t;//将接收的源IP地址输出；
                arp_rx_type <= (opcode == 16'd1) ? 1'b0 : 1'b1;//接收ARP数据报的类型；
            end
            else begin//如果接收的协议是IP协议；
                data_checksum <= (eth_rx_type == 2'd2) ? reply_checksum_add : data_checksum;//如果是ICMP，需要计算数据段的校验和。
            end
            rx_done <= 1'b1;//将接收一帧数据完成信号拉高一个时钟周期；
        end
        else begin
            rx_done <= 1'b0;
        end
    end

endmodule