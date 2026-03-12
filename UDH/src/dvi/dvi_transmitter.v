module dvi_transmitter(
    input                   clk         ,//系统时钟信号，
    input                   clk_5x      ,//频率为系统时钟5倍的时钟信号；
    input                   rst_n       ,//系统复位，低电平有效；
    
    input   [23 : 0]        video_din   ,//RGB888视频输入信号；
    input                   video_hsync ,//行同步信号；
    input                   video_vsync ,//场同步信号；
    input                   video_de    ,//像素使能信号；
    
    output                  tmds_clk_p  ,// TMDS 时钟通道
    output                  tmds_clk_n  ,
    output  [2 : 0]         tmds_data_p ,// TMDS 数据通道
    output  [2 : 0]         tmds_data_n  
    //output                  tmds_oen     // TMDS 输出使能
); 
    wire [9 : 0] tms_out    [3 : 0]         ;
    wire [3 : 0]            tmds_data_serial;
    wire [3 : 0]            tmds_out_p      ;
    wire [3 : 0]            tmds_out_n      ;

    //assign tmds_oen = 1'b1;//将双向的HDMI接口设置为输出。
    
    //对三个颜色通道进行编码
    dvi_tmds_encoder u_dvi_tmds_b (
        .clk    (clk            ),//系统时钟信号；
        .rst_n  (rst_n          ),//系统复位信号，高电平有效；
        .din    (video_din[7:0] ),//输入待编码数据;
        .c0	    (video_hsync    ),//控制信号C0;
        .c1	    (video_vsync    ),//控制信号c1;
        .de	    (video_de       ),//输入数据有效指示信号；
        .q_out  (tms_out[0][9:0]) //编码输出数据;
    );

    dvi_tmds_encoder u_dvi_tmds_g (
        .clk    (clk            ),
        .rst_n  (rst_n          ),
        .din    (video_din[15:8]),
        .c0     (1'b0           ),
        .c1     (1'b0           ),
        .de     (video_de       ),
        .q_out  (tms_out[1][9:0])
    );

    dvi_tmds_encoder u_dvi_tmds_r (
        .clk    (clk            ),
        .rst_n  (rst_n          ),
        .din    (video_din[23:16]),
        .c0	    (1'b0           ),
        .c1	    (1'b0           ),
        .de	    (video_de       ),
        .q_out  (tms_out[2][9:0])
    );

    assign tms_out[3][9 : 0] = 10'b11_1110_0000;//时钟信号编码后的数据为10'b11_1110_0000；
    
    generate
        genvar i;
        for(i=0 ; i<4 ; i = i + 1)begin : SER
            //对编码后的数据进行并串转换;
            serializer_10_to_1 u_serializer(
                .rst                (~rst_n             ),// 复位,高有效
                .clk                (clk                ),// 输入并行数据时钟
                .clk_5x             (clk_5x             ),// 输入串行数据时钟
                .paralell_data      (tms_out[i][9:0]    ),// 输入并行数据
                .serial_data_out    (tmds_data_serial[i]) // 输出串行数据
            );
            //转换差分信号;
            OBUFDS #(
                .IOSTANDARD ("DEFAULT"  )//I/O电平标准为TMDS
            )
            TMDS0 (
                .I  (tmds_data_serial[i]),
                .O  (tmds_out_p[i]     ),
                .OB (tmds_out_n[i]     ) 
            );
        end
    endgenerate
    
    assign tmds_clk_p = tmds_out_p[3];
    assign tmds_clk_n = tmds_out_n[3];
    assign tmds_data_p = tmds_out_p[2 : 0];
    assign tmds_data_n = tmds_out_n[2 : 0];
    
endmodule