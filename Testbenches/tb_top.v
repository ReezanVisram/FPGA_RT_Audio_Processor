`timescale 1ns / 1ps
module tb_top;
  // Parameters
  localparam SYSCLK_PERIOD = 10;
  localparam NUM_SAMPLES = 44100;
  localparam DATA_WIDTH = 32;
  localparam SCREEN_WIDTH=640;
  localparam SCREEN_HEIGHT=480;
  localparam ADDR_WIDTH=$clog2(SCREEN_WIDTH * SCREEN_HEIGHT);
  localparam SAMPLE_WIDTH=24;
  localparam COORD_WIDTH=16;

  reg resetn = 1'b0;

  // Clock signals + Generation
  reg clk_100MHz = 1'b0;
  wire clk_22_579MHz;
  wire clk_25_2MHz;
  wire locked;

  // Reading Samples
  reg signed [DATA_WIDTH - 1:0] sample_memory [0:NUM_SAMPLES - 1];
  reg signed [DATA_WIDTH - 1:0] sample;
  integer sample_line;

  // I2S Clocks
  wire mclk;
  wire sck;
  wire ws;

  // Sample Output
  reg sdin_pre;
  reg sdin;

  // Sample Input
  wire sdout;

  // AXI Signals
  wire rx_tready;
  wire rx_tvalid;
  wire signed [DATA_WIDTH - 1:0] rx_tdata;
  wire rx_tlast;

  wire tx_to_br_tready;
  wire br_to_tx_tvalid;
  wire signed [DATA_WIDTH - 1:0] br_to_tx_tdata;
  wire br_to_tx_tlast;

  wire conv_to_br_tready;
  wire br_to_conv_tvalid;
  wire signed [DATA_WIDTH - 1:0] br_to_conv_tdata;
  wire br_to_conv_tlast;

  // Mono Sample
  wire mono_sample_valid;
  wire signed [SAMPLE_WIDTH - 1:0] mono_sample;

  // FIFO Control
  wire fifo_empty;
  wire fifo_almost_empty;
  wire fifo_full;
  wire fifo_almost_full;

  // Sample To Pixel Signals
  wire signed [SAMPLE_WIDTH - 1:0] fifo_to_stp_mono_sample;
  wire stp_to_fifo_rd_en;
  wire [ADDR_WIDTH - 1:0] stp_to_fb_pixel_addr;
  wire stp_to_fb_pixel_data;
  wire stp_to_fb_pixel_wr_en;

  // VGA Controller Signals
  wire fb_to_controller_pixel_data;
  wire controller_to_fb_rd_en;
  wire [ADDR_WIDTH - 1:0] controller_to_fb_pixel_addr;
  wire [3:0] red;
  wire [3:0] green;
  wire [3:0] blue;
  wire hsync;
  wire vsync;
  wire data_enable;
  wire frame_pulse;
  wire line_pulse;

  // Framebuffer Manager
  wire [ADDR_WIDTH - 1:0] fbuffer_mgr_pixel_addr;
  wire fbuffer_mgr_pixel_data;
  wire fbuffer_mgr_pixel_wr_en;
  wire fbuffer_mgr_clearing_framebuffer;
  wire buffer_sel;

  wire fb_to_controller_pixel_data0;
  wire fb_to_controller_pixel_data1;

  wire [ADDR_WIDTH - 1:0] fbuffer_wr_addr;
  wire fbuffer_wr_data;
  wire fbuffer_wr_en;

  // UART Signals
  reg uart_rx_data_in = 1'b1; // Just idle for the purposes of this testbench
  wire uart_data_valid;
  wire [7:0] uart_data;
  wire uart_tx_active;
  wire uart_tx_data_out;
  wire uart_tx_done;

  // File I/O
  integer f;
  integer i;
  integer j;
  reg [999:0] filename;

  clk_wiz_0 clk_generator(
    .clk_in1(clk_100MHz),
    .clk_22_579MHz(clk_22_579MHz),
    .clk_25_2MHz(clk_25_2MHz),
    .locked(locked)
  );

  i2s_controller i2s_master(
    .clk(clk_22_579MHz),
    .resetn(resetn),
    .mclk(mclk),
    .sck(sck),
    .ws(ws)
  );

  i2s_receive i2s_rx(
    .M_AXIS_ACLK(clk_22_579MHz),
    .M_AXIS_ARESETN(resetn),
    .M_AXIS_TREADY(rx_tready),
    .M_AXIS_TVALID(rx_tvalid),
    .M_AXIS_TDATA(rx_tdata),
    .M_AXIS_TLAST(rx_tlast),
    
    .sck(sck),
    .ws(ws),
    .sd(sdin)
  );

  axi4_stream_broadcaster broadcaster(
    .AXIS_ACLK(clk_22_579MHz),
    .AXIS_ARESETN(resetn),
    .S_AXIS_TDATA(rx_tdata),
    .S_AXIS_TVALID(rx_tvalid),
    .S_AXIS_TLAST(rx_tlast),
    .S_AXIS_TREADY(rx_tready),

    .M_AXIS_TDATA1(br_to_tx_tdata),
    .M_AXIS_TVALID1(br_to_tx_tvalid),
    .M_AXIS_TLAST1(br_to_tx_tlast),
    .M_AXIS_TREADY1(tx_to_br_tready),

    .M_AXIS_TDATA2(br_to_conv_tdata),
    .M_AXIS_TVALID2(br_to_conv_tvalid),
    .M_AXIS_TLAST2(br_to_conv_tlast),
    .M_AXIS_TREADY2(conv_to_br_tready)
  );

  i2s_transmit i2s_tx(
    .S_AXIS_ACLK(clk_22_579MHz),
    .S_AXIS_ARESETN(resetn),
    .S_AXIS_TDATA(br_to_tx_tdata),
    .S_AXIS_TLAST(br_to_tx_tlast),
    .S_AXIS_TVALID(br_to_tx_tvalid),
    .S_AXIS_TREADY(tx_to_br_tready),

    .sck(sck),
    .ws(ws),
    .sd(sdout)
  );

  packet_to_mono_sample_converter conv(
    .S_AXIS_ACLK(clk_22_579MHz),
    .S_AXIS_ARESETN(resetn),
    .S_AXIS_TDATA(br_to_conv_tdata),
    .S_AXIS_TLAST(br_to_conv_tlast),
    .S_AXIS_TVALID(br_to_conv_tvalid),
    .S_AXIS_TREADY(conv_to_br_tready),

    .mono_sample_valid(mono_sample_valid),
    .mono_sample(mono_sample)
  );

  fifo_generator_0 mono_sample_fifo (
    .wr_clk(clk_22_579MHz),
    .rd_clk(clk_100MHz),
    .din(mono_sample),
    .wr_en(mono_sample_valid),
    .rd_en(stp_to_fifo_rd_en),
    .dout(fifo_to_stp_mono_sample),
    .full(fifo_full),
    .almost_full(fifo_almost_full),
    .empty(fifo_empty),
    .almost_empty(fifo_almost_empty)
  );

  sample_to_pixel stp(
    .clk(clk_100MHz),
    .resetn(resetn),
    .frame_pulse(frame_pulse),
    .mono_sample(fifo_to_stp_mono_sample),
    .fifo_almost_empty(fifo_almost_empty),
    .clearing_framebuffer(fbuffer_mgr_clearing_framebuffer),
    .fifo_rd_en(stp_to_fifo_rd_en),
    .pixel_addr(stp_to_fb_pixel_addr),
    .pixel_data(stp_to_fb_pixel_data),
    .pixel_wr_en(stp_to_fb_pixel_wr_en)
  );

  framebuffer_manager fbuffer_mgr(
    .clk(clk_100MHz),
    .resetn(resetn),
    .frame_pulse(frame_pulse),
    .pixel_addr(fbuffer_mgr_pixel_addr),
    .pixel_wr_en(fbuffer_mgr_pixel_wr_en),
    .pixel_data(fbuffer_mgr_pixel_data),
    .clearing_framebuffer(fbuffer_mgr_clearing_framebuffer),
    .buffer_sel(buffer_sel)
  );

  framebuffer fbuffer0(
    .wrclk(clk_100MHz),
    .rdclk(clk_25_2MHz),
    .resetn(resetn),
    .wr_en(buffer_sel && fbuffer_wr_en),
    .rd_en(controller_to_fb_rd_en),
    .wr_addr(fbuffer_wr_addr),
    .rd_addr(controller_to_fb_pixel_addr),
    .wr_data(fbuffer_wr_data),
    .rd_data(fb_to_controller_pixel_data0)
  );

  framebuffer fbuffer1(
    .wrclk(clk_100MHz),
    .rdclk(clk_25_2MHz),
    .resetn(resetn),
    .wr_en(!buffer_sel && fbuffer_wr_en),
    .rd_en(controller_to_fb_rd_en),
    .wr_addr(fbuffer_wr_addr),
    .rd_addr(controller_to_fb_pixel_addr),
    .wr_data(fbuffer_wr_data),
    .rd_data(fb_to_controller_pixel_data1)
  );

  vga_controller controller(
    .clk(clk_25_2MHz),
    .resetn(resetn),
    .pixel_data(fb_to_controller_pixel_data),
    .framebuffer_rd_en(controller_to_fb_rd_en),
    .pixel_addr(controller_to_fb_pixel_addr),
    .red(red),
    .blue(blue),
    .green(green),
    .hsync(hsync),
    .vsync(vsync),
    .data_enable(data_enable),
    .frame_pulse(frame_pulse),
    .line_pulse(line_pulse)
  );

  uart_rx uartrx(
    .clk(clk_25_2MHz),
    .resetn(resetn),
    .rx_data(uart_rx_data_in),
    .data_valid(uart_data_valid),
    .data(uart_data)
  );

  uart_tx uarttx(
    .clk(clk_25_2MHz),
    .resetn(resetn),
    .data_valid(uart_data_valid),
    .data(uart_data),
    .tx_active(uart_tx_active),
    .tx_data(uart_tx_data_out),
    .tx_done(uart_tx_done)
  );

  initial
  begin
    $timeformat(-9, 2, " ns", 20);
    wait(locked == 1'b1);
    resetn = 1'b1;

    $readmemb("samples.txt", sample_memory);

    wait(ws == 1'b1);
    wait(ws == 1'b0);
    for (sample_line = 0; sample_line < NUM_SAMPLES; sample_line = sample_line + 1)
    begin
      sample = 32'h00000000;

      repeat(DATA_WIDTH) // We want to output the 24 bit sample, then another 8 cycles of don't cares
      begin
        sdin_pre <= sample[DATA_WIDTH - 1];
        sdin <= sdin_pre;
        sample <= sample << 1;
        @(negedge sck);
      end
    end

    #900 $finish;
  end

  always @(posedge frame_pulse)
  begin
    $sformat(filename, "memory0_%d.txt", ((sample_line*2)/640));
    f = $fopen(filename, "w");

    for (i = 0; i < SCREEN_HEIGHT; i = i + 1)
    begin
      for (j = 0; j < SCREEN_WIDTH; j = j + 1)
      begin
        $fwrite(f, "%0b", fbuffer0.ram[i * SCREEN_WIDTH + j]);
      end
      $fwrite(f, "\n");
    end

    $fclose(f);
    
    $sformat(filename, "memory1_%d.txt", ((sample_line*2)/640));
    f = $fopen(filename, "w");

    for (i = 0; i < SCREEN_HEIGHT; i = i + 1)
    begin
      for (j = 0; j < SCREEN_WIDTH; j = j + 1)
      begin
        $fwrite(f, "%0b", fbuffer1.ram[i * SCREEN_WIDTH + j]);
      end
      $fwrite(f, "\n");
    end

    $fclose(f);
  end

  always
  begin
    #(SYSCLK_PERIOD/2) clk_100MHz <= ~clk_100MHz;
  end

  assign fbuffer_wr_addr = fbuffer_mgr_clearing_framebuffer ? fbuffer_mgr_pixel_addr : stp_to_fb_pixel_addr;
  assign fbuffer_wr_data = fbuffer_mgr_clearing_framebuffer ? fbuffer_mgr_pixel_data : stp_to_fb_pixel_data;
  assign fbuffer_wr_en = fbuffer_mgr_clearing_framebuffer ? fbuffer_mgr_pixel_wr_en : stp_to_fb_pixel_wr_en;
  assign fb_to_controller_pixel_data = buffer_sel ? fb_to_controller_pixel_data1 : fb_to_controller_pixel_data0;

endmodule