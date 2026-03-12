module ddr3_rw #(
    parameter   PINGPANG_EN         =       1'b0                ,//乒乓操作是否使能；
    parameter   USE_ADDR_W          =       29                  ,//用户需要写入数据的位宽；
    parameter   USE_BUST_LEN_W      =       8                   ,//用户侧读写数据突发长度的位宽；
    parameter   USE_DATA_W          =       16                  ,//用户侧读写数据的位宽；
    parameter   DDR_ADDR_W          =       29                  ,//MIG IP读写数据地址位宽；
    parameter   DDR_DATA_W          =       128                  //MIG IP读写数据的位宽；
)(
    //MIG IP用户侧接口信号
    input                                   ui_clk              ,//mig ip 用户时钟；
    input                                   ui_clk_sync_rst     ,//复位,高有效；
    input                                   init_calib_complete ,//DDR3初始化完成；
    input                                   app_rdy             ,//MIG IP核空闲；
    input                                   app_wdf_rdy         ,//MIG写FIFO空闲；
    input       [DDR_DATA_W - 1 : 0]        app_rd_data         ,//MIG读出数据；
    input                                   app_rd_data_valid   ,//MIG读出数据有效指示信号；
    output                                  app_en              ,//MIG IP核操作使能；
    output      [2:0]                       app_cmd             ,//MIG IP核操作命令，读或者写；
    output reg  [DDR_ADDR_W - 1 : 0]        app_addr            ,//DDR3地址；
    output                                  app_wdf_wren        ,//用户写使能   
    output                                  app_wdf_end         ,//突发写当前时钟最后一个数据 
    output      [DDR_DATA_W - 1 : 0]        app_wdf_data        ,//DDR3写数据；
    //写FIFO相关信号
    input                                   wfifo_empty         ,//写FIFO空指示信号；
    input                                   wfifo_rd_rst_busy   ,//写FIFO的复位忙指示信号，高电平表示处于复位状态；
    input       [DDR_DATA_W - 1 : 0]        wfifo_rdata         ,//写FIFO读数据；
    input       [USE_BUST_LEN_W : 0]        wfifo_rdata_count   ,//写FIFO读侧的数据个数；
    output                                  wfifo_rd_en         ,//写FIFO读使能；
    output                                  wfifo_wr_rst        ,//写FIFO复位信号；
    //读FIFO相关信号
    input                                   rfifo_full          ,//读FIFO满指示信号；
    input                                   rfifo_wr_rst_busy   ,//读FIFO的复位忙指示信号，高电平表示处于复位状态；
    input       [USE_BUST_LEN_W : 0]        rfifo_wdata_count   ,//读FIFO写侧的数据个数；
    output                                  rfifo_wr_en         ,//读FIFO写使能；
    output                                  rfifo_rd_rst        ,//读FIFO复位信号；
    output      [DDR_DATA_W - 1 : 0]        rfifo_wdata         ,//读FIFO写数据；
    //MIG IP读写数据突发地址限制
    input       [DDR_ADDR_W - 1 : 0]        app_addr_wr_min     ,//写DDR3的起始地址；
    input       [DDR_ADDR_W - 1 : 0]        app_addr_wr_max     ,//写DDR3的结束地址；
    input       [USE_BUST_LEN_W - 1 : 0]    app_wr_bust_len     ,//向DDR3中写数据时的突发长度；
    input       [DDR_ADDR_W - 1 : 0]        app_addr_rd_min     ,//读DDR3的起始地址；
    input       [DDR_ADDR_W - 1 : 0]        app_addr_rd_max     ,//读DDR3的结束地址；
    input       [USE_BUST_LEN_W - 1 : 0]    app_rd_bust_len     ,//从DDR3中读数据时的突发长度；
    input                                   wr_rst              ,//写复位信号，上升沿有效，持续时间必须大于ui_clk的周期；
    input                                   rd_rst               //读复位信号，下降沿沿有效，持续时间必须大于ui_clk周期；
);
    localparam  IDLE                =       4'b0001             ;//空闲状态;
    localparam  DONE                =       4'b0010             ;//DDR3初始化完成状态;
    localparam  WRITE               =       4'b0100             ;//读FIFO保持状态;
    localparam  READ                =       4'b1000             ;//写FIFO保持状态;

    reg                                     wfifo_wr_rst = 1'b0 ;
    reg                                     rfifo_rd_rst = 1'b0 ;
    reg         [3 : 0]                     state_c             ;
    reg         [3 : 0]                     state_n             ;
    reg         [1 : 0]                     wr_rst_r            ;//
    reg         [1 : 0]                     rd_rst_r            ;//
    reg                                     ddr3_read_valid     ;//DDR3 读使能；
    reg         [USE_BUST_LEN_W - 1 : 0]    bust_cnt            ;//
    reg         [USE_BUST_LEN_W - 1 : 0] 	bust_cnt_num        ;//
    reg         [4 : 0]                     wr_rst_cnt          ;//
    reg         [4 : 0]                     rd_rst_cnt          ;//
    reg         [DDR_ADDR_W - 4 : 0]        app_addr_wr         ;
    reg         [DDR_ADDR_W - 4 : 0]        app_addr_rd         ;
    

    wire       		                        add_bust_cnt        ;
    wire       		                        end_bust_cnt        ;
    wire                                    rst_n               ;//复位信号，低电平有效；

    assign rst_n = ~ui_clk_sync_rst;//将MIG IP输出的复位信号取反作为复位信号；

    //状态机在写状态MIG空闲且写有效，或者状态机在读状态MIG空闲时加1，其余时间为低电平；
    assign app_en = ((state_c == WRITE && app_rdy && app_wdf_rdy) || (state_c == READ && app_rdy));
    assign app_wdf_wren = (state_c == WRITE && app_rdy && app_wdf_rdy);//状态机在写状态且写入数据有效时拉高；
    assign app_wdf_end = app_wdf_wren;//由于DDR3芯片时钟和用户时钟的频率4:1，突发长度为8，故两个信号相同；
    assign app_cmd = (state_c == READ) ? 3'd1 :3'd0;//处于读的时候命令值为1，其他时候命令值为0;
    assign wfifo_rd_en = app_wdf_wren;//写FIFO读使能信号，读出数据与读使能对齐。
    assign app_wdf_data = wfifo_rdata;//将写FIFO读出的数据传输给MIG IP的写数据；
    assign rfifo_wr_en = app_rd_data_valid;//将MIG IP输出数据有效指示信号作为读FIFO的写使能信号；
    assign rfifo_wdata = app_rd_data;//将从MIG IP读出的数据作为读FIFO的写数据；
    
    //状态机次态到现态的跳转；
    always@(posedge ui_clk or negedge rst_n)begin
        if(!rst_n)begin//初始为空闲状态；
            state_c <= IDLE;
        end
        else begin
            state_c <= state_n;
        end
    end
    
    //状态机次态的跳转；
    always@(*)begin
        case(state_c)
            IDLE : begin
                if(init_calib_complete)begin//如果DDR3初始化完成，跳转到DDR3初始化完成状态；
                    state_n = DONE;
                end
                else begin
                    state_n = state_c;
                end
            end
            DONE : begin//如果写FIFO中数据多于一次写突发的长度且写FIFO不处于复位状态时，跳转到写状态；
                if((wfifo_rdata_count >= app_wr_bust_len - 2) && (~wfifo_rd_rst_busy))begin
                    state_n = WRITE;
                end//如果读FIFO中的数据少于一次读突发的长度且读FIFO不处于复位状态时，开始读出数据；
                else if((rfifo_wdata_count < app_rd_bust_len - 2) && ddr3_read_valid && (~rfifo_wr_rst_busy))begin
                    state_n = READ;
                end
                else begin
                    state_n = state_c;
                end
            end
            WRITE : begin
                if(end_bust_cnt || wfifo_wr_rst)begin//写入指定个数的数据回到完成状态或者写复位信号有效；
                    state_n = DONE;
                end
                else begin
                    state_n = state_c;
                end
            end
            READ : begin
                if(end_bust_cnt || rfifo_rd_rst)begin//读出指定个数的数据回到完成状态或者读复位信号有效；
                    state_n = DONE;
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

    //突发读写个数计数器bust_cnt，用于记录突发读写的数据个数；
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0；
            bust_cnt <= 0;
        end
        else if(state_c == DONE)begin//状态机位于初始化完成状态时清零；
            bust_cnt <= 0;
        end
        else if(add_bust_cnt)begin
            if(end_bust_cnt)
                bust_cnt <= 0;
            else
                bust_cnt <= bust_cnt + 1;
        end
    end
    
    //状态机在写状态MIG空闲且写有效且写FIFO中有数据，或者状态机在读状态MIG空闲且读FIFO未满时加1，其余时间为低电平；
    assign add_bust_cnt = ((state_c == WRITE && app_rdy && app_wdf_rdy) || (state_c == READ && app_rdy));
    assign end_bust_cnt = add_bust_cnt && bust_cnt == bust_cnt_num;//读写的突发长度可能不同，所以需要根据状态机的状态判断读写状态最大值；

    //用于存储突发的最大长度；
    always@(posedge ui_clk)begin
        if(state_c == READ)begin//如果状态机位于读状态，则计数器的最大值对应读突发的长度；
            bust_cnt_num <= app_rd_bust_len - 1;
        end
        else begin//否则为写突发的长度；
            bust_cnt_num <= app_wr_bust_len - 1;
        end
    end

    //生成MIG IP的写地址，初始值为写入数据的最小地址。
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            app_addr_wr <= app_addr_wr_min;
        end
        else if(wfifo_wr_rst)begin//复位时地址回到最小值；
            app_addr_wr <= app_addr_wr_min;
        end
        //当计数器加以条件有效且状态机处于写状态时，如果写入地址达到最大，则进行复位操作，否则加8；
        else if(add_bust_cnt && (state_c == WRITE))begin
            if(app_addr_wr >= app_addr_wr_max - 8)
                app_addr_wr <= app_addr_wr_min;
            else//否则，每次地址加8，因为DDR3每次突发会写入8次数据；
                app_addr_wr <= app_addr_wr + 8;
        end
    end

    //生成MIG IP的读地址，初始值为读出数据的最小地址。
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            app_addr_rd <= app_addr_rd_min;
        end
        else if(rfifo_rd_rst)begin//复位时地址回到最小值；
            app_addr_rd <= app_addr_rd_min;
        end
        else if(add_bust_cnt && (state_c == READ))begin
            if(app_addr_rd >= app_addr_rd_max - 8)begin
                app_addr_rd <= app_addr_rd_min;
            end
            else
                app_addr_rd <= app_addr_rd + 8;
        end
    end

    //根据是否使用乒乓功能，综合成不同的电路；
    generate
        if(PINGPANG_EN)begin//如果使能乒乓操作，地址信号将执行下列信号；
            reg  waddr_page ;
            reg  raddr_page ;
            //相当于把bank地址进行调整，使得读写的地址空间不再同一个范围；
            always@(posedge ui_clk)begin
                if(rst_n==1'b0)begin
                    waddr_page <= 1'b1;
                    raddr_page <= 1'b0;
                end
                else if(add_bust_cnt)begin
                    if((state_c == WRITE) && (app_addr_wr >= app_addr_wr_max - 8))
                        waddr_page <= ~waddr_page;
                    else if((state_c == READ) && (app_addr_rd >= app_addr_rd_max - 8))
                        raddr_page <= ~waddr_page;
                end
            end
            //将数据读写地址赋给ddr地址
            always @(*) begin
                if(state_c == READ )
                    app_addr <= {2'b0,raddr_page,app_addr_rd[25:0]};
                else
                    app_addr <= {2'b0,waddr_page,app_addr_wr[25:0]};
            end
        end
        else begin//如果没有使能乒乓操作，则综合以下代码；
            //将数据读写地址赋给ddr地址
            always @(*) begin
                if(state_c == READ )
                    app_addr <= {3'b0,app_addr_rd[25:0]};
                else
                    app_addr <= {3'b0,app_addr_wr[25:0]};
            end
        end
    endgenerate

    //生成读使能信号，最开始的时候DDR3中并没有数据，必须向DDR3中写入数据后才能从DDR3中读取数据；
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            ddr3_read_valid <= 1'b0;
        end//当状态机位于写状态写入一帧数据之后拉高，之后保持高电平不变。
        else if(app_addr_wr >= app_addr_wr_max - 8)begin
            ddr3_read_valid <= 1'b1;
        end
    end

    //后面考虑复位信号的处理，复位的时候应该对FIFO和写地址一起复位，复位FIFO需要复位信号持续多个时钟周期；
    //因此需要计数器，由于读写的复位是独立的，可能同时到达，因此计数器不能共用。
    //写复位到达时，如果状态机位于写数据状态，应该回到初始状态，等待清零完成后再进行跳转。
    //同步两个FIFO复位信号，并且检测上升沿，用于清零读写DDR的地址，由于状态机跳转会检测FIFO是否位于复位状态。
    always@(posedge ui_clk)begin
        wr_rst_r <= {wr_rst_r[0],wr_rst};//同步复位脉冲信号；
        rd_rst_r <= {rd_rst_r[0],rd_rst};//同步复位脉冲信号；
    end

    //生成写复位信号，由于需要对写FIFO进行复位，所以复位信号必须持续多个时钟周期；
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            wfifo_wr_rst <= 1'b0;
        end
        else if(wr_rst_r[0] && (~wr_rst_r[1]))begin//检测wfifo_wr_rst上升沿拉高复位信号；
            wfifo_wr_rst <= 1'b1;
        end//当写复位计数器全为高电平时拉低，目前是持续32个时钟周期，如果不够，修改wrst_cnt位宽即可。
        else if(&wr_rst_cnt)begin
            wfifo_wr_rst <= 1'b0;
        end
    end
    
    //写复位计数器，初始值为0，之后一直对写复位信号持续的时钟个数进行计数；
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            wr_rst_cnt <= 0;
        end
        else if(wfifo_wr_rst)begin
            wr_rst_cnt <= wr_rst_cnt + 1;
        end
    end

    //写复位信号，初始值为0，当读FIFO读复位下降沿到达时有效，当计数器计数结束时清零；
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            rfifo_rd_rst <= 1'b0;
        end
        else if(rd_rst_r[0] && (~rd_rst_r[1]))begin
            rfifo_rd_rst <= 1'b1;
        end
        else if(&rd_rst_cnt)begin
            rfifo_rd_rst <= 1'b0;
        end
    end
    
    //读复位计数器，初始值为0，当读复位有效时进行计数；
    always@(posedge ui_clk)begin
        if(rst_n==1'b0)begin//初始值为0;
            rd_rst_cnt <= 0;
        end
        else if(rfifo_rd_rst)begin
            rd_rst_cnt <= rd_rst_cnt + 1;
        end
    end

endmodule