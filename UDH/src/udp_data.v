module udp_data(
    input                       clk             ,//时钟信号;
    input                       rst_n           ,//复位信号，低电平有效;

    input       [7 : 0]         din             ,//输入数据；
    input                       din_vld         ,//输入数据有效指示信号；

    output  reg [15 : 0]        dout            ,//输出16为并行数据；
    output  reg                 dout_vld         //输出数据有效指示信号，高电平有效；
);
    reg                         din_vld_r       ;//

    //生成像素有效指示信号，以太网每次穿8位数据，传输两次合成一个像素数据；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            din_vld_r <= 1'b0;
        end
        else if(din_vld)begin
            din_vld_r <= ~din_vld_r;
        end
    end

    //将输入的8位数据合成16位数据，先接收高8位数据；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            dout <= 16'd0;
        end
        else if(din_vld)begin
            if(din_vld_r)
                dout[7 : 0] <= din;
            else//先接收高8位数据；
                dout[15 : 8] <= din;
        end
    end

    //当输入数据有效且是低八位数据时，表示接收到完整十六位数据了，拉高输出有效指示信号；
    always@(posedge clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            dout_vld <= 1'b0;
        end
        else begin
            dout_vld <= din_vld & din_vld_r;
        end
    end
    
endmodule