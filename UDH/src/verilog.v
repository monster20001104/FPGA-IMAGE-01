module max_multiplier_pipelined (
    input clk,
    input rst,
    input data_valid,
    input [15:0] a [0:63],
    input [15:0] b [0:63],
    output reg [31:0] max_product,
    output reg data_max_valid
);

    // 流水线寄存器
    reg [31:0] stage1_max [0:31];  // 第一级比较结果
    reg [31:0] stage2_max [0:15];  // 第二级比较结果
    reg [31:0] stage3_max [0:7];   // 第三级比较结果
    reg [31:0] stage4_max [0:3];   // 第四级比较结果
    reg [31:0] stage5_max [0:1];   // 第五级比较结果
    
    // 计算所有乘积
    wire [31:0] products [0:63];
    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : PRODUCT_GEN
            assign products[i] = a[i] * b[i];
        end
    endgenerate
    
    // 流水线处理
    always @(posedge clk) begin
        if (rst) begin
            max_product <= 32'b0;
            data_max_valid <= 1'b0;
        end else begin
            // 第一级流水：两两比较，64->32
            for (integer j = 0; j < 32; j = j + 1) begin
                stage1_max[j] <= (products[2*j] > products[2*j+1]) ? 
                                products[2*j] : products[2*j+1];
            end
            
            // 第二级流水：32->16
            for (integer j = 0; j < 16; j = j + 1) begin
                stage2_max[j] <= (stage1_max[2*j] > stage1_max[2*j+1]) ? 
                                stage1_max[2*j] : stage1_max[2*j+1];
            end
            
            // 第三级流水：16->8
            for (integer j = 0; j < 8; j = j + 1) begin
                stage3_max[j] <= (stage2_max[2*j] > stage2_max[2*j+1]) ? 
                                stage2_max[2*j] : stage2_max[2*j+1];
            end
            
            // 第四级流水：8->4
            for (integer j = 0; j < 4; j = j + 1) begin
                stage4_max[j] <= (stage3_max[2*j] > stage3_max[2*j+1]) ? 
                                stage3_max[2*j] : stage3_max[2*j+1];
            end
            
            // 第五级流水：4->2
            for (integer j = 0; j < 2; j = j + 1) begin
                stage5_max[j] <= (stage4_max[2*j] > stage4_max[2*j+1]) ? 
                                stage4_max[2*j] : stage4_max[2*j+1];
            end
            
            // 最终比较：2->1
            max_product <= (stage5_max[0] > stage5_max[1]) ? 
                          stage5_max[0] : stage5_max[1];
            
            // 延迟有效信号以匹配流水线
            data_max_valid <= data_valid;  // 需要根据实际延迟调整
        end
    end

endmodule