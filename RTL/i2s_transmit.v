module i2s_transmit
#(
  parameter DATA_WIDTH=32
)
(
  input S_AXIS_ACLK,
  input S_AXIS_ARESETN,
  input [DATA_WIDTH - 1:0] S_AXIS_TDATA,
  input S_AXIS_TLAST,
  input S_AXIS_TVALID,

  output reg S_AXIS_TREADY,
  
  input sck,
  input ws,
  output reg sd
);


  wire wsp;
  reg wsd;
  reg wsdd;
  wire sck_rise;
  wire sck_fall;

  reg [DATA_WIDTH - 1:0] data;
  reg [DATA_WIDTH - 1:0] data_left;
  reg [DATA_WIDTH - 1:0] data_right;

  reg [1:0] sck_sync;
  always @(posedge S_AXIS_ACLK)
  begin
    sck_sync <= {sck_sync, sck};
  end

  always @(posedge S_AXIS_ACLK)
  begin
    if (sck_rise)
    begin
      wsd <= ws;
    end
    wsdd <= wsd;  
  end

  always @(posedge S_AXIS_ACLK)
  begin
    if (!S_AXIS_ARESETN)
      data <= {DATA_WIDTH{1'b0}};
    else if (wsp)
      data <= wsd ? data_right : data_left;
    else if (sck_rise)
      data <= {data, 1'b0};
  end

  always @(negedge sck)
    sd <= data[DATA_WIDTH - 1];

  always @(posedge S_AXIS_ACLK)
  begin
    if (!S_AXIS_ARESETN)
      S_AXIS_TREADY <= 1'b0;
    else if (S_AXIS_TREADY && S_AXIS_TVALID)
      S_AXIS_TREADY <= 1'b0;
    else if (wsp && S_AXIS_TLAST == wsd)
      S_AXIS_TREADY <= 1'b1;
  end

  always @(posedge S_AXIS_ACLK)
  begin
    if (S_AXIS_TREADY && S_AXIS_TVALID && !S_AXIS_TLAST)
      data_left <= S_AXIS_TDATA;
    else if (S_AXIS_TREADY && S_AXIS_TVALID && S_AXIS_TLAST)
      data_right <= S_AXIS_TDATA;
  end

  assign wsp = wsd ^ wsdd;
  assign sck_rise = sck_sync == 2'b01;
  assign sck_fall = sck_sync == 2'b10;
endmodule