//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：http://www.openedv.com/forum.php
//淘宝店铺：https://zhengdianyuanzi.tmall.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2023-2033
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           line_shift_ram_8bit
// Last modified Date:  2020/05/04 9:19:08
// Last Version:        V1.0
// Descriptions:        line_shift_ram_8bit
//                      
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/05/04 9:19:08
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//
module line_shift_ram_8bit(
    input          clock,   
    input          clken,
    input          pre_frame_href, //行信号
    
    input   [7:0]  shiftin,  
    output  [7:0]  taps0x,   
    output  [7:0]  taps1x    
);

//reg define
reg  [2:0]  clken_dly;
reg  [9:0]  ram_rd_addr;
reg  [9:0]  ram_rd_addr_d0;
reg  [9:0]  ram_rd_addr_d1;
reg  [7:0]  shiftin_d0;
reg  [7:0]  shiftin_d1;
reg  [7:0]  shiftin_d2;
reg  [7:0]  taps0x_d0;

//*****************************************************
//**                    main code
//*****************************************************

//在数据来到时，ram地址累加
always@(posedge clock)begin
    if(pre_frame_href)
        if(clken)
            ram_rd_addr <= ram_rd_addr + 1 ;
        else
            ram_rd_addr <= ram_rd_addr ;
    else
        ram_rd_addr <= 0 ;
end

//时钟使能信号延迟三拍
always@(posedge clock) begin
    clken_dly <= { clken_dly[1:0] , clken };
end

//将ram地址延迟二拍
always@(posedge clock ) begin
    ram_rd_addr_d0 <= ram_rd_addr;
    ram_rd_addr_d1 <= ram_rd_addr_d0;
end

//输入数据延迟三拍
always@(posedge clock)begin
    shiftin_d0 <= shiftin;
    shiftin_d1 <= shiftin_d0;
    shiftin_d2 <= shiftin_d1;
end

//用于存储前一行图像的RAM
blk_mem_gen_0  u_ram_1024x8_0(    
    .clka  (clock), 
    .wea   (clken_dly[2]),    //在延迟的第三个时钟周期，当前行的数据写入RAM0
    .addra (ram_rd_addr_d1),
    .dina  (shiftin_d2),
    .clkb  (clock),
    .addrb (ram_rd_addr),
    .doutb (taps0x)           //延迟一个时钟周期，输出RAM0中前一行图像的数据
); 

//用于存储前前一行图像的RAM
blk_mem_gen_0  u_ram_1024x8_1(    
    .clka   (clock),           
    .wea   (clken_dly[2]),    //在延迟的第三个时钟周期，将前一行图像的数据写入RAM1
    .addra (ram_rd_addr_d1),
    .dina  (taps0x),
    .clkb  (clock),
    .addrb (ram_rd_addr),
    .doutb (taps1x)           //延迟一个时钟周期，输出RAM1中前前一行图像的数据
); 

endmodule 