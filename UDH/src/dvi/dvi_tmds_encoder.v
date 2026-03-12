module dvi_tmds_encoder(
    input									    clk		        ,//系统时钟信号；
    input									    rst_n  	        ,//系统复位信号，低电平有效；

    input				[7 : 0]	                din		        ,//输入待编码数据;
    input                                       c0              ,//控制信号C0;
    input                                       c1              ,//控制信号c1;
    input                                       de              ,//输入数据有效指示信号；
    output reg			[9 : 0]	                q_out	         //编码输出数据;
);
    localparam          CTRLTOKEN0      =       10'b1101010100  ;
    localparam          CTRLTOKEN1      =       10'b0010101011  ;
    localparam          CTRLTOKEN2      =       10'b0101010100  ;
    localparam          CTRLTOKEN3      =       10'b1010101011  ;
    
    reg                 [7 : 0]                 din_r           ;//
    reg                 [1 : 0]                 de_r,c0_r,c1_r  ;
    reg                 [3 : 0]                 n1d,n1q_m,n0q_m ;
    reg                 [5 : 0]                 cnt             ;
    reg                 [8 : 0]                 q_m_r           ;

    wire                [8 : 0]                 q_m             ;//
    wire                                        condition1      ;
    wire                                        condition2      ;
    wire                                        condition3      ;
    //统计待编码输入数据中1的个数，最多8个1，所以位宽为4。
    always@(posedge clk)begin
        if(~rst_n)begin//初始值为0;
            n1d <= 4'd0;
        end
        else if(de)begin//当DE为高电平，统计输入数据中1的个数。
            n1d <= din[0] + din[1] + din[2] + din[3] + din[4] + din[5] + din[6] + din[7];
        end
        else begin//当DE为低电平时，对控制信号编码，此时不需要统计输入信号中1的个数，故清零。
            n1d <= 4'd0;
        end
    end
    
    //移位寄存器将输入数据暂存，与后续信号对齐。
    always@(posedge clk)begin
        din_r   <= din;
        de_r    <= {de_r[0],de};
        c0_r    <= {c0_r[0],c0};
        c1_r    <= {c1_r[0],c1};
        q_m_r   <= q_m;
    end

    //判断条件1，输入数据1的个数多余4或者1的个数等于4并且最低位为0时拉高，其余时间拉低。
    assign condition1 = ((n1d > 4'd4) || ((n1d == 4'd4) && (~din_r[0])));
    
    //对输入的信号进行异或运算。
    assign q_m[0] = din_r[0];
    assign q_m[1] = condition1 ? ~((q_m[0] ^ din_r[1])) : (q_m[0] ^ din_r[1]);
    assign q_m[2] = condition1 ? ~((q_m[1] ^ din_r[2])) : (q_m[1] ^ din_r[2]);
    assign q_m[3] = condition1 ? ~((q_m[2] ^ din_r[3])) : (q_m[2] ^ din_r[3]);
    assign q_m[4] = condition1 ? ~((q_m[3] ^ din_r[4])) : (q_m[3] ^ din_r[4]);
    assign q_m[5] = condition1 ? ~((q_m[4] ^ din_r[5])) : (q_m[4] ^ din_r[5]);
    assign q_m[6] = condition1 ? ~((q_m[5] ^ din_r[6])) : (q_m[5] ^ din_r[6]);
    assign q_m[7] = condition1 ? ~((q_m[6] ^ din_r[7])) : (q_m[6] ^ din_r[7]);
    assign q_m[8] = ~condition1;
    
    always@(posedge clk)begin
        if(~rst_n)begin//初始值为0;
            n1q_m <= 4'd0;
            n0q_m <= 4'd0;
        end
        else if(de_r[0])begin//对输入有效数据时，q_m中1和0的个数进行统计；
            n1q_m <= q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7];
            n0q_m <= 4'd8 - (q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7]);
        end
        else begin//输入数据无效时清零。
            n1q_m <= 4'd0;
            n0q_m <= 4'd0;
        end
    end

    //判断条件2，一行已编码数据中1的个数等于0的个数或者本次编码数据中1的个数等于0的个数。
    assign condition2 = ((cnt == 6'd0) || (n1q_m == n0q_m));
    //判断条件3，已编码数据中1的多余0并且本次编码中间数据1的个数也多与0的个数或者已编码数据中0的个数较多并且此次编码中0的个数也比较多时拉高，其余时间拉低。
    assign condition3 = (((~cnt[5]) && (n1q_m > n0q_m)) || (cnt[5] && (n1q_m < n0q_m)));

    always@(posedge clk)begin
        if(~rst_n)begin//初始值为0;
            cnt <= 6'd0;
            q_out <= 10'd0;
        end
        else if(de_r[1])begin
            q_out[8] <= q_m_r[8];//第8位为编码方式位，直接输出即可。
            if(condition2)begin
                q_out[9] <= ~q_m_r[8];
                q_out[7:0] <= q_m_r[8] ? q_m_r[7:0] : ~q_m_r[7:0];
                //进行cnt的计算；
                cnt <= q_m_r[8] ? (cnt + n1q_m - n0q_m) : (cnt + n0q_m - n1q_m);
            end
            else if(condition3)begin
                q_out[9] <= 1'b1;
                q_out[7:0] <= ~q_m_r[7:0];
                //进行cnt的计算；
                cnt <= cnt + {q_m_r[8],1'b0} + n0q_m - n1q_m;
            end
            else begin
                q_out[9] <= 1'b0;
                q_out[7:0] <= q_m_r[7:0];
                //进行cnt的计算；
                cnt <= cnt - {~q_m_r[8],1'b0} + n1q_m - n0q_m;
            end
        end
        else begin
            cnt <= 6'd0;//对控制信号进行编码时，将计数器清零。
            case ({c1_r[1],c0_r[1]})
                2'b00   : q_out <= CTRLTOKEN0;
                2'b01   : q_out <= CTRLTOKEN1;
                2'b10   : q_out <= CTRLTOKEN2;
                2'b11   : q_out <= CTRLTOKEN3;
            endcase
        end
    end

endmodule