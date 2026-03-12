//以太网发送数据模块；
//信号名中与IUDP字符的，表示ICMP协议和UDP协议共用信号，具体表示哪种协议由eth_type的值决定。
module eth_tx #(
    parameter       BOARD_MAC       =   48'h00_11_22_33_44_55       ,//开发板MAC地址 00-11-22-33-44-55；
    parameter       BOARD_IP        =   {8'd192,8'd168,8'd1,8'd10}  ,//开发板IP地址 192.168.1.10；
    parameter       DES_MAC         =   48'hff_ff_ff_ff_ff_ff       ,//目的MAC地址 ff_ff_ff_ff_ff_ff；
    parameter       DES_IP          =   {8'd192,8'd168,8'd1,8'd102} ,//目的IP地址 192.168.1.102；
    parameter       BOARD_PORT      =   16'd1234                    ,//开发板的UDP端口号；
    parameter       DES_PORT        =   16'd5678                    ,//目的端口号；
    parameter       IP_TYPE         =   16'h0800                    ,//16'h0800表示IP协议；
    parameter       ARP_TYPE        =   16'h0806                     //16'h0806表示ARP协议；
)( 
    input                               clk                         ,//时钟信号；
    input                               rst_n                       ,//复位信号，低电平有效；
    
    input                               eth_tx_start                ,//开始发送信号。
    
    input           [47 : 0]            des_mac                     ,//发送的目标MAC地址；
    input           [31 : 0]            des_ip                      ,//发送的目标IP地址；

    output reg      [1 : 0]             eth_tx_type_r               ,//正在发送的数据报类型；
    output reg                          iudp_tx_data_req            ,//需要发送数据的请求信号，与需要发送的数据对齐。
    input           [7 : 0]             iudp_tx_data                ,//以太网需要发送的数据，延后tx_data_req一个时钟周期；
    
    input           [15 : 0]            iudp_tx_byte_num            ,//ICMP或UDP数据段需要发送的数据。
    
    input           [1 : 0]             eth_tx_type                 ,//发送以太网数据报的类型，1表示ARP，2表示ICMP，3表示UDP。
    input                               arp_tx_type                 ,//ARP数据报文类型，0表示请求数据报，1表示应答数据报文。
    input           [7 : 0]             icmp_tx_type                ,//ICMP数据报的类型；
    input           [7 : 0]             icmp_tx_code                ,//ICMP数据的代码；
    input           [15 : 0]            icmp_tx_id                  ,//ICMP数据包的ID；
    input           [15 : 0]            icmp_tx_seq                 ,//ICMP数据报文的标识符；
    input           [31 : 0]            icmp_data_checksum          ,//ICMP数据段校验和；
    input           [31 : 0]            crc_out                     ,//CRC校验数据；
    output  reg                         crc_en                      ,//CRC开始校验使能；
    output  reg                         crc_clr                     ,//CRC数据复位信号；
    output  reg     [7 : 0]             crc_data                    ,//输出给CRC校验模块进行计算的数据；
    output  reg                         gmii_tx_en                  ,//GMII输出数据有效信号；
    output  reg     [7 : 0]             gmii_txd                    ,//GMII输出数据；
    output  reg                         rdy                          //模块忙闲指示信号，高电平表示该模块处于空闲状态；
);
    localparam      IDLE            =   9'b00000_0001               ;//初始状态，等待开始发送信号;
    localparam      PREAMBLE        =   9'b00000_0010               ;//发送前导码+帧起始界定符;
    localparam      ETH_HEAD        =   9'b00000_0100               ;//发送以太网帧头;
    localparam      IP_HEAD         =   9'b00000_1000               ;//发送IP帧头;
    localparam      IUDP_HEAD       =   9'b00001_0000               ;//发送ICMP或UDP帧头;
    localparam      IUDP_DATA       =   9'b00010_0000               ;//发送ICMP或UDP协议数据；
    localparam      ARP_DATA        =   9'b00100_0000               ;//发送ARP数据段；
    localparam      CRC             =   9'b01000_0000               ;//发送CRC校验值;
    localparam      IFG             =   9'b10000_0000               ;//帧间隙，也就是传输96bit的时间，对应12Byte数据。

    localparam      MIN_DATA_NUM    =   16'd18                      ;//以太网数据最小46个字节，IP首部20个字节+UDP首部8个字节，所以数据至少46-20-8=18个字节。

    reg                                 gmii_tx_en_r                ;//
    reg             [47 : 0]            des_mac_r                   ;//
    reg             [31 : 0]            des_ip_r                    ;
    reg             [8 : 0]	            state_n                     ;
    reg             [8 : 0]	            state_c                     ;
    reg             [15 : 0] 	        cnt                         ;//
    reg             [15 : 0]            cnt_num                     ;//
    reg             [15 : 0]            iudp_tx_byte_num_r          ;
    reg             [31 : 0]            ip_head             [4 : 0] ;
    reg             [31 : 0]            iudp_head           [1 : 0] ;//
    reg             [7 : 0]             arp_data            [17 : 0];
    reg             [15 : 0]            ip_total_num                ;
    reg             [31 : 0]            ip_head_check               ;//IP头部校验码；
    reg             [31 : 0]            icmp_check                  ;//ICMP校验；
    
    wire       		                    add_cnt                     ;
    wire       		                    end_cnt                     ;
    
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            ip_head[0] <= 32'd0;
            ip_head[1] <= {16'd0,16'h4000};//高16位表示标识，每次发送数据后会加1，低16位表示不分片。
            ip_head[2] <= 32'd0;
            ip_head[3] <= 32'd0;
            ip_head[4] <= 32'd0;
            iudp_head[0] <= 32'd0;
            iudp_head[1] <= 32'd0;
            arp_data[0] <= 8'd0;
            arp_data[1] <= 8'd0;
            arp_data[2] <= 8'd0;
            arp_data[3] <= 8'd0;
            arp_data[4] <= 8'd0;
            arp_data[5] <= 8'd0;
            arp_data[6] <= 8'd0;
            arp_data[7] <= 8'd0;
            arp_data[8] <= 8'd0;
            arp_data[9] <= 8'd0;
            arp_data[10] <= 8'd0;
            arp_data[11] <= 8'd0;
            arp_data[12] <= 8'd0;
            arp_data[13] <= 8'd0;
            arp_data[14] <= 8'd0;
            arp_data[15] <= 8'd0;
            arp_data[16] <= 8'd0;
            arp_data[17] <= 8'd0;
            icmp_check  <= 32'd0;
            ip_head_check <= 32'd0;//IP头部校验和；
            des_mac_r <= DES_MAC;
            des_ip_r <= DES_IP;
            iudp_tx_byte_num_r <= MIN_DATA_NUM;
            ip_total_num <= MIN_DATA_NUM + 28;
            eth_tx_type_r <= 0;
        end
        //在状态机空闲状态下，上游发送使能信号时，将目的MAC地址和目的IP的数据进行暂存。
        else if(state_c == IDLE && eth_tx_start)begin
            if(eth_tx_type == 2'd1)begin//如果需要发送ARP报文；
                arp_data[0] <= 8'h00;//ARP硬件类型;
                arp_data[1] <= 8'h01;
                arp_data[2] <= 8'h08;//发送协议类型;
                arp_data[3] <= 8'h00;
                arp_data[4] <= 8'h06;//硬件地址长度；
                arp_data[5] <= 8'h04;//协议地址长度；
                arp_data[6] <= 8'h00;//发送ARP操作类型；
                arp_data[7] <= arp_tx_type ? 8'h02 : 8'h01;
                arp_data[8] <= BOARD_MAC[47 : 40];//源MAC地址；
                arp_data[9] <= BOARD_MAC[39 : 32];
                arp_data[10] <= BOARD_MAC[31 : 24];
                arp_data[11] <= BOARD_MAC[23 : 16];
                arp_data[12] <= BOARD_MAC[15 : 8];
                arp_data[13] <= BOARD_MAC[7 : 0];
                arp_data[14] <= BOARD_IP[31 : 24];//源IP地址；
                arp_data[15] <= BOARD_IP[23 : 16];
                arp_data[16] <= BOARD_IP[15 : 8];
                arp_data[17] <= BOARD_IP[7 : 0];
            end
            else if(eth_tx_type == 2'd2)begin//发送ICMP协议数据报；
                iudp_head[0][31 : 16] <= {icmp_tx_type,icmp_tx_code};//存储ICMP的类型和代码。
                iudp_head[1] <= {icmp_tx_id,icmp_tx_seq};//存储ICMP的标识符和ID；
                ip_head[2] <= {8'h80,8'd1,16'd0};//分别表示生存时间，协议类型，1表示ICMP，6表示TCP，17表示UDP协议，低16位校验和先默认为0；
                iudp_tx_byte_num_r <= iudp_tx_byte_num;//把数据段的长度暂存；
                icmp_check <= icmp_data_checksum;//ICMP的校验和初始值为数据端的校验和。
            end
            else if(eth_tx_type == 2'd3)begin//发送UDP协议数据报；
                iudp_head[0] <= {BOARD_PORT,DES_PORT};//16位源端口和目的端口地址。
                iudp_head[1][31 : 16] <= (((iudp_tx_byte_num >= MIN_DATA_NUM) ? iudp_tx_byte_num : MIN_DATA_NUM) + 8);//计算UDP需要发送报文的长度。
                iudp_head[1][15 : 0] <= 16'd0;//UDP的校验和设置为0。
                ip_head[2] <= {8'h80,8'd17,16'd0};//分别表示生存时间，协议类型，1表示ICMP，6表示TCP，17表示UDP协议，低16位校验和先默认为0；
                iudp_tx_byte_num_r <= iudp_tx_byte_num;//把数据段的长度暂存；
            end
            eth_tx_type_r <= eth_tx_type;//把以太网数据报的类型暂存；
            //如果需要发送的数据多余最小长度要求，则发送的总数居等于需要发送的数据加上UDP和IP帧头数据。
            ip_total_num <= (((iudp_tx_byte_num >= MIN_DATA_NUM) ? iudp_tx_byte_num : MIN_DATA_NUM) + 28);
            if((des_mac != 48'd0) && (des_ip != 32'd0))begin//当接收到目的MAC地址和目的IP地址时更新。
                des_ip_r <= des_ip;
                des_mac_r <= des_mac;
            end
            else begin
                des_ip_r <= DES_IP;
                des_mac_r <= DES_MAC;
            end
        end
        //在发送以太网帧头时，就开始计算IP帧头和ICMP的校验码，并将计算结果存储，便于后续直接发送。
        else if(state_c == ETH_HEAD && add_cnt)begin
            case (cnt)
                16'd0 : begin//初始化需要发送的IP头部数据。
                    ip_head[0] <= {8'h45,8'h00,ip_total_num[15 : 0]};//依次表示IP版本号，IP头部长度，IP服务类型，IP包的总长度。
                    ip_head[3] <= BOARD_IP;//源IP地址。
                    ip_head[4] <= des_ip_r;//目的IP地址。
                end
                16'd1 : begin//开始计算IP头部校验和数据，并且将计算结果存储到对应位置。
                    ip_head_check <= ip_head[0][31 : 16] + ip_head[0][15 : 0];
                    if(eth_tx_type == 2'd2)
                        icmp_check <= icmp_check + iudp_head[0][31 : 16];
                end
                16'd2 : begin
                    ip_head_check <= ip_head_check + ip_head[1][31 : 16];
                    if(eth_tx_type == 2'd2)
                        icmp_check <= icmp_check + iudp_head[1][31 : 16];
                end
                16'd3 : begin
                    ip_head_check <= ip_head_check + ip_head[1][15 : 0];
                    if(eth_tx_type == 2'd2)
                        icmp_check <= icmp_check + iudp_head[1][15 : 0];
                end
                16'd4 : begin
                    ip_head_check <= ip_head_check + ip_head[2][31 : 16];
                    if(eth_tx_type == 2'd2)
                        icmp_check <= icmp_check[31 : 16] + icmp_check[15 : 0];//可能出现进位,累加一次。
                end
                16'd5 : begin
                    ip_head_check <= ip_head_check + ip_head[3][31 : 16];
                    if(eth_tx_type == 2'd2)
                        icmp_check <= icmp_check[31 : 16] + icmp_check[15 : 0];//可能出现进位,累加一次。
                end
                16'd6 : begin
                    ip_head_check <= ip_head_check + ip_head[3][15 : 0];
                    if(eth_tx_type == 2'd2)
                        iudp_head[0][15 : 0] <= ~icmp_check[15 : 0];//按位取反得到校验和。
                end
                16'd7 : begin
                    ip_head_check <= ip_head_check + ip_head[4][31 : 16];
                end
                16'd8 : begin
                    ip_head_check <= ip_head_check + ip_head[4][15 : 0];
                end
                16'd9,16'd10 : begin
                    ip_head_check <= ip_head_check[31 : 16] + ip_head_check[15 : 0];
                end
                16'd11 : begin
                    ip_head[2][15:0] <= ~ip_head_check[15 : 0];
                end
                default: begin
                    ip_head_check <= 32'd0;//校验和清零，用于下次计算。
                end
            endcase
        end
        else if(state_c == IP_HEAD && end_cnt)
            ip_head[1] <= {ip_head[1][31 : 16]+1,16'h4000};//高16位表示标识，每次发送数据后会加1，低16位表示不分片。
    end

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
                if(eth_tx_start && (eth_tx_type != 2'd0))begin//在空闲状态接收到上游发出的使能信号；
                    state_n = PREAMBLE;
                end
                else begin
                    state_n = state_c;
                end
            end
            PREAMBLE:begin
                if(end_cnt)begin//发送完前导码和SFD；
                    state_n = ETH_HEAD;
                end
                else begin
                    state_n = state_c;
                end
            end
            ETH_HEAD:begin
                if(end_cnt)begin//发送完以太网帧头数据；
                    if(~eth_tx_type_r[1])//如果发送ARP数据，则跳转到发送ARP数据状态；
                        state_n = ARP_DATA;
                    else//否则跳转到发送IP首部状态；
                        state_n = IP_HEAD;
                end
                else begin
                    state_n = state_c;
                end
            end
            IP_HEAD:begin
                if(end_cnt)begin//发送完IP帧头数据；
                    state_n = IUDP_HEAD;
                end
                else begin
                    state_n = state_c;
                end
            end
            IUDP_HEAD:begin
                if(end_cnt)begin//发送完UDP帧头数据；
                    state_n = IUDP_DATA;
                end
                else begin
                    state_n = state_c;
                end
            end
            IUDP_DATA:begin
                if(end_cnt)begin//发送完udp协议数据；
                    state_n = CRC;
                end
                else begin
                    state_n = state_c;
                end
            end
            ARP_DATA:begin
                if(end_cnt)begin//发送完ARP数据；
                    state_n = CRC;
                end
                else begin
                    state_n = state_c;
                end
            end
            CRC:begin
                if(end_cnt)begin//发送完CRC校验码；
                    state_n = IFG;
                end
                else begin
                    state_n = state_c;
                end
            end
            IFG:begin
                if(end_cnt)begin//延时帧间隙对应时间。
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

    //计数器，用于记录每个状态机每个状态需要发送的数据个数，每个时钟周期发送1byte数据。
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
    end
    
    assign add_cnt = (state_c != IDLE);//状态机不在空闲状态时计数。
    assign end_cnt = add_cnt && cnt == cnt_num - 1;//状态机对应状态发送完对应个数的数据。
    
    //状态机在每个状态需要发送的数据个数。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为20;
            cnt_num <= 16'd20;
        end
        else begin
            case (state_c)
                PREAMBLE : cnt_num <= 16'd8;//发送7个前导码和1个8'hd5。
                ETH_HEAD : cnt_num <= 16'd14;//发送14字节的以太网帧头数据。
                IP_HEAD : cnt_num <= 16'd20;//发送20个字节是IP帧头数据。
                IUDP_HEAD : cnt_num <= 16'd8;//发送8字节的UDP帧头数据。
                IUDP_DATA : if(iudp_tx_byte_num_r >= MIN_DATA_NUM)//如果需要发送的数据多余以太网最短数据要求，则发送指定个数数据。
                                cnt_num <= iudp_tx_byte_num_r;
                            else//否则需要将指定个数数据发送完成，不足长度补零，达到最短的以太网帧要求。
                                cnt_num <= MIN_DATA_NUM;
                ARP_DATA : cnt_num <= 16'd46;//ARP数据阶段，发送46字节数据；
                CRC : cnt_num <= 16'd5;//CRC在时钟1时才开始发送数据，这是因为CRC计算模块输出的数据会延后一个时钟周期。
                IFG : cnt_num <= 16'd12;//帧间隙对应时间为12Byte数据传输时间。
                default: cnt_num <= 16'd20;
            endcase
        end
    end

    //根据状态机和计数器的值产生输出数据，只不过这不是真正的输出，还需要延迟一个时钟周期。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            crc_data <= 8'd0;
        end
        else if(add_cnt)begin
            case (state_c)
                PREAMBLE : if(end_cnt)
                                crc_data <= 8'hd5;//发送1字节SFD编码；
                            else
                                crc_data <= 8'h55;//发送7字节前导码；
                ETH_HEAD : if(cnt < 6)
                                crc_data <= des_mac_r[47 - 8*cnt -: 8];//发送目的MAC地址，先发高字节；
                            else if(cnt < 12)
                                crc_data <= BOARD_MAC[47 - 8*(cnt-6) -: 8];//发送源MAC地址，先发高字节；
                            else if(cnt == 12)
                                crc_data <= 8'h08;//发送源以太网协议类型，先发高字节；
                            else
                                crc_data <= eth_tx_type_r[1] ? 8'h00 : 8'h06;//如果高位有效，表示发送IP协议，否则ARP协议。
                ARP_DATA : if(cnt < 18)
                                crc_data <= arp_data[cnt];
                            else if(cnt < 24)
                                crc_data <= des_mac_r[47 - 8*(cnt - 18) -: 8];//发送目的MAC地址，先发高字节；
                            else if(cnt < 28)
                                crc_data <= des_ip_r[31 - 8*(cnt - 24) -: 8];//发送目的IP地址，先发高字节；
                            else//后面18位数据补0；
                                crc_data <= 8'd0;
                IP_HEAD : if(cnt < 4)//发送IP帧头。
                                crc_data <= ip_head[0][31 - 8*cnt -: 8];
                            else if(cnt < 8)
                                crc_data <= ip_head[1][31 - 8*(cnt-4) -: 8];
                            else if(cnt < 12)
                                crc_data <= ip_head[2][31 - 8*(cnt-8) -: 8];
                            else if(cnt < 16)
                                crc_data <= ip_head[3][31 - 8*(cnt-12) -: 8];
                            else 
                                crc_data <= ip_head[4][31 - 8*(cnt-16) -: 8];
                IUDP_HEAD : if(cnt < 4)//发送UDP帧头数据。
                                crc_data <= iudp_head[0][31 - 8*cnt -: 8];
                            else
                                crc_data <= iudp_head[1][31 - 8*(cnt-4) -: 8];
                IUDP_DATA : if(iudp_tx_byte_num_r >= MIN_DATA_NUM)//需要判断发送的数据是否满足以太网最小数据要求。
                                crc_data <= iudp_tx_data;//如果满足最小要求，将需要配发送的数据输出。
                            else if(cnt < iudp_tx_byte_num_r)//不满足最小要求时，先将需要发送的数据发送完。
                                crc_data <= iudp_tx_data;//将需要发送的数据输出即可。
                            else//剩余数据补充0。
                                crc_data <= 8'd0;
                default : ;
            endcase
        end
    end

    //生成数据请求输入信号，外部输入数据延后该信号三个时钟周期，所以需要提前产生三个时钟周期产生请求信号；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            iudp_tx_data_req <= 1'b0;
        end
        //在数据段的前三个时钟周期拉高；
        else if(state_c == IUDP_HEAD && add_cnt && (cnt == cnt_num - 4))begin
            iudp_tx_data_req <= 1'b1;
        end//在ICMP或者UDP数据段时，当发送完数据的前三个时钟拉低；
        else if(iudp_tx_byte_num_r >= MIN_DATA_NUM)begin//发送的数据段长度大于等于18.
            if(state_c == IUDP_DATA && add_cnt && (cnt == cnt_num - 4))begin
                iudp_tx_data_req <= 1'b0;
            end
        end
        else begin//发送的数据段长度小于4；
            if(state_c == IUDP_HEAD && (iudp_tx_byte_num_r <= 3) && add_cnt && (cnt == cnt_num + iudp_tx_byte_num_r - 4))begin
                iudp_tx_data_req <= 1'b0;
            end//发送的数据段有效长度大于等于4，小于18时；
            else if(state_c == IUDP_DATA && (iudp_tx_byte_num_r > 3) && add_cnt && (cnt == iudp_tx_byte_num_r - 4))begin
                iudp_tx_data_req <= 1'b0;
            end
        end
    end

    //生成一个crc_data指示信号，用于生成gmii_txd信号。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            gmii_tx_en_r <= 1'b0;
        end
        else if(state_c == CRC)begin
            gmii_tx_en_r <= 1'b0;
        end
        else if(state_c == PREAMBLE)begin
            gmii_tx_en_r <= 1'b1;
        end
    end

    //生产CRC校验模块使能信号，初始值为0，当开始输出以太网帧头时拉高，当ARP和以太网帧头数据全部输出后拉低。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            crc_en <= 1'b0;
        end
        else if(state_c == CRC)begin//当ARP和以太网帧头数据全部输出后拉低.
            crc_en <= 1'b0;
        end//当开始输出以太网帧头时拉高。
        else if(state_c == ETH_HEAD && add_cnt)begin
            crc_en <= 1'b1;
        end
    end

    //生产CRC校验模块清零信号，状态机处于空闲时清零。
    always@(posedge clk)begin
        crc_clr <= (state_c == IDLE);
    end

    //生成gmii_txd信号，默认输出0。
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            gmii_txd <= 8'd0;
        end//在输出CRC状态时，输出CRC校验码，先发送低位数据。
        else if(state_c == CRC && add_cnt && cnt > 0)begin
            gmii_txd <= crc_out[(8*cnt - 1) -: 8];
        end//其余时间如果crc_data有效，则输出对应数据。
        else if(gmii_tx_en_r)begin
            gmii_txd <= crc_data;
        end
    end

    //生成gmii_txd有效指示信号。
    always@(posedge clk)begin
        gmii_tx_en <= gmii_tx_en_r || (state_c == CRC);
    end

    //模块忙闲指示信号，当接收到上游模块的使能信号或者状态机不处于空闲状态时拉低，其余时间拉高。
    //该信号必须使用组合逻辑产生，上游模块必须使用时序逻辑检测该信号。
    always@(*)begin
        if(eth_tx_start || state_c != IDLE)
            rdy = 1'b0;
        else
            rdy = 1'b1;
    end

endmodule