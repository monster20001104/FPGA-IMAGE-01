//****************************************************************************************//
// 模块名称: vip_matrix_generate_3x3_8bit
// 功能描述: 生成 3x3 图像矩阵，并加入了完美的图像边界像素复制 (Edge Padding) 修复逻辑
//****************************************************************************************//
module  vip_matrix_generate_3x3_8bit
(
    input             clk,  
    input             rst_n,

    input             pre_frame_vsync,
    input             pre_frame_href,
    input             pre_frame_clken,
    input      [7:0]  pre_img_y,
    
    output            matrix_frame_vsync,
    output            matrix_frame_href,
    output            matrix_frame_clken,
    output reg [7:0]  matrix_p11,
    output reg [7:0]  matrix_p12, 
    output reg [7:0]  matrix_p13,
   
    output reg [7:0]  matrix_p21, 
    output reg [7:0]  matrix_p22, 
    output reg [7:0]  matrix_p23,
    output reg [7:0]  matrix_p31, 
    output reg [7:0]  matrix_p32, 
    output reg [7:0]  matrix_p33
);

// wire/reg define
wire [7:0] row1_data;  
wire [7:0] row2_data;  
wire       read_frame_href;
wire       read_frame_clken;
wire       read_frame_vsync; // 用于同步后的场信号提取

reg  [7:0] pre_img_y_d[2:0];
reg  [7:0] row3_data;
reg  [4:0] pre_frame_vsync_r;
reg  [4:0] pre_frame_href_r;
reg  [4:0] pre_frame_clken_r;

// --- 新增：边缘检测与像素复制逻辑相关的寄存器与信号 ---
reg  [11:0] row_cnt;
reg  [11:0] col_cnt;
reg         read_frame_href_d0;
wire        read_frame_href_pos;
wire [7:0]  row1_pad;
wire [7:0]  row2_pad;
wire [7:0]  row3_pad;
// ------------------------------------------------

//*****************************************************
//** main code
//*****************************************************

assign read_frame_vsync   = pre_frame_vsync_r[3];
assign read_frame_href    = pre_frame_href_r[3] ;
assign read_frame_clken   = pre_frame_clken_r[3];

assign matrix_frame_vsync = pre_frame_vsync_r[4];
assign matrix_frame_href  = pre_frame_href_r[4] ;
assign matrix_frame_clken = pre_frame_clken_r[4];

// 当前数据延迟4拍后放在第3行
always@(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        row3_data <= 0;
        pre_img_y_d[0] <= 0;
        pre_img_y_d[1] <= 0;
        pre_img_y_d[2] <= 0;  
    end
    else begin
        pre_img_y_d[0] <= pre_img_y;
        pre_img_y_d[1] <= pre_img_y_d[0];
        pre_img_y_d[2] <= pre_img_y_d[1];
        row3_data <= pre_img_y_d[2];
    end
end

// 用于存储列数据的RAM (2行深度的Shift RAM)
line_shift_ram_8bit  u_line_shift_ram_8bit
(
    .clock          (clk),
    .clken          (pre_frame_clken),
    .pre_frame_href (pre_frame_href),
    .shiftin        (pre_img_y),   
    .taps0x         (row2_data),   
    .taps1x         (row1_data)    
);

// 将同步信号延迟5拍，用于同步化处理
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pre_frame_vsync_r <= 0;
        pre_frame_href_r  <= 0;
        pre_frame_clken_r <= 0;
    end
    else begin
        pre_frame_vsync_r <= {pre_frame_vsync_r[3:0] , pre_frame_vsync};
        pre_frame_href_r  <= {pre_frame_href_r[3:0]  , pre_frame_href };
        pre_frame_clken_r <= {pre_frame_clken_r[3:0] , pre_frame_clken};
    end
end

// =========================================================================
// ==================== 核心修改：增加图像边缘像素复制补偿 ====================
// =========================================================================

// 1. 提取 href 的上升沿，用于行计数
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        read_frame_href_d0 <= 1'b0;
    else
        read_frame_href_d0 <= read_frame_href;
end
assign read_frame_href_pos = read_frame_href && !read_frame_href_d0;

// 2. 行计数器 (Row Counter)：用于处理顶部边界
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        row_cnt <= 12'd0;
    else if(!read_frame_vsync)    // 场同步(消隐区)期间清零
        row_cnt <= 12'd0;
    else if(read_frame_href_pos)  // 每来新的一行，计数器加1
        row_cnt <= row_cnt + 1'b1;
end

// 3. 列计数器 (Column Counter)：用于处理左侧边界
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        col_cnt <= 12'd0;
    else if(!read_frame_href)     // 行消隐期间清零
        col_cnt <= 12'd0;
    else if(read_frame_clken)     // 有效像素进入时累加
        col_cnt <= col_cnt + 1'b1;
end

// 4. 纵向边缘补偿 (Top Edge Padding)
// 根据当前帧处理到的行数，动态拦截并替换 RAM 输出的上一帧脏数据
assign row1_pad = (row_cnt == 12'd1) ? row3_data : ((row_cnt == 12'd2) ? row2_data : row1_data);
assign row2_pad = (row_cnt == 12'd1) ? row3_data : row2_data;
assign row3_pad = row3_data;

// 5. 在同步处理后的控制信号下，输出图像矩阵
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        {matrix_p11, matrix_p12, matrix_p13} <= 24'h0;
        {matrix_p21, matrix_p22, matrix_p23} <= 24'h0;
        {matrix_p31, matrix_p32, matrix_p33} <= 24'h0;
    end
    else if(read_frame_href) begin
        if(read_frame_clken) begin
            if(col_cnt == 12'd0) begin
                // 横向补偿：一行的第1个像素，直接广播赋值给矩阵的左、中、右三列！
                {matrix_p11, matrix_p12, matrix_p13} <= {row1_pad, row1_pad, row1_pad};
                {matrix_p21, matrix_p22, matrix_p23} <= {row2_pad, row2_pad, row2_pad};
                {matrix_p31, matrix_p32, matrix_p33} <= {row3_pad, row3_pad, row3_pad};
            end else begin
                // 正常滑动：新数据移入右列，旧数据左移
                {matrix_p11, matrix_p12, matrix_p13} <= {matrix_p12, matrix_p13, row1_pad};
                {matrix_p21, matrix_p22, matrix_p23} <= {matrix_p22, matrix_p23, row2_pad};
                {matrix_p31, matrix_p32, matrix_p33} <= {matrix_p32, matrix_p33, row3_pad};
            end
        end
    end
    // 【注】：去除了 else 里的强制清零逻辑。
    // 在 HBLANK 期间保持最后一个像素不变，这就实现了天然的右侧边缘像素复制。
end

endmodule