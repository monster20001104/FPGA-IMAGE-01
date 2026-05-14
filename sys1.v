`timescale 1ns / 1ps

module unaligned_data_packer (
    input  logic        clk,
    input  logic        rst_n,

    // --- 上游数据流接口 ---
    input  logic        din_vld,       // 数据有效信号
    input  logic [31:0] din_data,      // 32-bit (4字节) 输入数据
    input  logic [2:0]  din_vld_bytes, // 本拍有效的字节数: 1, 2, 3, 4 (当 din_vld=1 时有效)
    input  logic        flush,         // 尾部冲刷脉冲 (一整条数据流结束，强制把残余数据写进RAM)

    // --- 下游观测/RAM接口 ---
    // 为了方便您测试，把2行RAM的数据直接作为端口输出
    output logic [31:0] ram_data_0,    
    output logic [31:0] ram_data_1,
    output logic        ram_written_pulse // 提示当拍RAM被成功写入
);

    // =========================================================================
    // 1. 核心状态寄存器 (齿轮箱的核心)
    // =========================================================================
    logic [1:0]  offset;         // 记录当前蓄水池里有几个残留字节 (范围: 0, 1, 2, 3)
    logic [31:0] leftover_reg;   // 蓄水池寄存器：暂存未能写进 RAM 的残余数据

    // =========================================================================
    // 2. RAM 实例定义 (2行，每行 32-bit)
    // =========================================================================
    logic [31:0] ram [0:1];      // 两行 RAM
    logic        ram_wptr;       // 写指针，只有 0 和 1 两个状态

    // =========================================================================
    // 3. 组合逻辑：中间计算变量
    // =========================================================================
    logic [31:0] din_masked;     // 掩码后的输入数据 (滤除高位的垃圾位)
    logic [63:0] data_concat;    // 64-bit 滑动窗口总线 (新老数据拼接处)
    logic [2:0]  total_bytes;    // 本拍的总有效字节数 = 残余字节数 + 新进字节数

    logic        ram_wen;        // RAM 写使能
    logic [31:0] ram_wdata;      // 准备写进 RAM 的 32-bit 数据

    // -------------------------------------------------------------------------
    // [步骤 A] 输入数据掩码处理 (Data Masking)
    // 物理意义：如果传来的包尾只有1个字节有效，我们必须把高位3个字节强行清零，
    // 防止未知的垃圾数据污染后续的拼接。
    // -------------------------------------------------------------------------
    always_comb begin
        if (din_vld) begin
            case (din_vld_bytes)
                3'd1: din_masked = {24'h0, din_data[7:0]};
                3'd2: din_masked = {16'h0, din_data[15:0]};
                3'd3: din_masked = {8'h0,  din_data[23:0]};
                3'd4: din_masked = din_data[31:0];
                default: din_masked = 32'h0;
            endcase
        end else begin
            din_masked = 32'h0;
        end
    end

    // -------------------------------------------------------------------------
    // [步骤 B] 64-bit 宽总线滑动拼接 (Sliding Window Concat)
    // 物理意义：把新来的数据根据现有的 offset 整体向左移位，
    // 然后和低位的 leftover_reg (旧数据) 做一次无缝的“或(OR)”拼接。
    // -------------------------------------------------------------------------
    assign data_concat = ({32'h0, din_masked} << (offset * 8)) | {32'h0, leftover_reg};

    // 计算当拍总共拥有的有效字节数
    assign total_bytes = din_vld ? (offset + din_vld_bytes) : offset;

    // -------------------------------------------------------------------------
    // [步骤 C] 写入控制与冲刷逻辑 (Write Control & Flush)
    // 物理意义：判断是凑齐了4个字节正常写入，还是被迫执行 Flush 补零写入。
    // -------------------------------------------------------------------------
    always_comb begin
        if (flush && offset > 0) begin
            // 触发冲刷：上游没数据了，强制把蓄水池里的尾巴写进 RAM。
            // 因为我们做过掩码，leftover_reg 的高位自动就是补0的 (Padding)。
            ram_wen   = 1'b1;
            ram_wdata = leftover_reg;
        end 
        else if (din_vld && total_bytes >= 3'd4) begin
            // 正常拼接：旧数据 + 新数据 >= 4字节，完美填满一行
            ram_wen   = 1'b1;
            ram_wdata = data_concat[31:0]; // 截取低32位写入RAM
        end 
        else begin
            // 数据不够 4 字节，安静地攒在蓄水池里，不写 RAM
            ram_wen   = 1'b0;
            ram_wdata = 32'h0;
        end
    end

    // =========================================================================
    // 4. 时序逻辑：状态更新与 RAM 写入
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位清零
            offset       <= 2'd0;
            leftover_reg <= 32'd0;
            ram_wptr     <= 1'b0;
            ram[0]       <= 32'd0;
            ram[1]       <= 32'd0;
        end else begin
            
            // ---> [动作 1] RAM 写入操作
            if (ram_wen) begin
                ram[ram_wptr] <= ram_wdata;
                ram_wptr      <= ~ram_wptr; // 0和1之间来回翻转 (Ping-Pong)
            end

            // ---> [动作 2] 齿轮箱状态更新
            if (flush && offset > 0) begin
                // Flush执行完毕后，所有状态复位，干干净净迎接未来的新包
                offset       <= 2'd0;
                leftover_reg <= 32'd0;
            end 
            else if (din_vld) begin
                // 更新 offset: 对 4 取模 (保留低2位即可)
                offset <= total_bytes[1:0]; 
                
                // 更新 leftover_reg 蓄水池
                if (total_bytes >= 3'd4) begin
                    // 写了一次 RAM，把截取剩下的高位残余落入蓄水池
                    leftover_reg <= data_concat[63:32];
                end else begin
                    // 不够写 RAM，所有数据全部落入蓄水池 (在低32位)
                    leftover_reg <= data_concat[31:0];
                end
            end
            
        end
    end

    // --- 信号绑定 (供外部观测) ---
    assign ram_data_0 = ram[0];
    assign ram_data_1 = ram[1];
    assign ram_written_pulse = ram_wen;

endmodule