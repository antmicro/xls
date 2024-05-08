module send_match(
  input wire clk,
  input wire rst,
  input wire send_match__channel_s_rdy,
  output wire send_match__channel_s,
  output wire send_match__channel_s_vld
);
  reg ____state;
  reg p0_valid;
  reg p1_valid;
  reg p2_valid;
  reg p3_valid;
  reg p4_valid;
  reg p5_valid;
  reg p6_valid;
  reg p7_valid;
  reg p8_valid;
  reg p9_valid;
  reg p10_valid;
  wire p10_enable;
  wire p9_enable;
  wire p8_enable;
  wire p7_enable;
  wire p6_enable;
  wire p5_enable;
  wire p4_enable;
  wire p3_enable;
  wire p2_enable;
  wire p1_enable;
  wire p0_enable;
  wire state;
  assign p10_enable = 1'h1;
  assign p9_enable = 1'h1;
  assign p8_enable = 1'h1;
  assign p7_enable = 1'h1;
  assign p6_enable = 1'h1;
  assign p5_enable = 1'h1;
  assign p4_enable = 1'h1;
  assign p3_enable = 1'h1;
  assign p2_enable = 1'h1;
  assign p1_enable = 1'h1;
  assign p0_enable = 1'h1;
  assign state = ~____state;
  always @ (posedge clk or posedge rst) begin
    if (rst) begin
      ____state <= 1'h0;
      p0_valid <= 1'h0;
      p1_valid <= 1'h0;
      p2_valid <= 1'h0;
      p3_valid <= 1'h0;
      p4_valid <= 1'h0;
      p5_valid <= 1'h0;
      p6_valid <= 1'h0;
      p7_valid <= 1'h0;
      p8_valid <= 1'h0;
      p9_valid <= 1'h0;
      p10_valid <= 1'h0;
    end else begin
      ____state <= send_match__channel_s_rdy ? state : ____state;
      p0_valid <= p0_enable ? send_match__channel_s_rdy : p0_valid;
      p1_valid <= p1_enable ? p0_valid : p1_valid;
      p2_valid <= p2_enable ? p1_valid : p2_valid;
      p3_valid <= p3_enable ? p2_valid : p3_valid;
      p4_valid <= p4_enable ? p3_valid : p4_valid;
      p5_valid <= p5_enable ? p4_valid : p5_valid;
      p6_valid <= p6_enable ? p5_valid : p6_valid;
      p7_valid <= p7_enable ? p6_valid : p7_valid;
      p8_valid <= p8_enable ? p7_valid : p8_valid;
      p9_valid <= p9_enable ? p8_valid : p9_valid;
      p10_valid <= p10_enable ? p9_valid : p10_valid;
    end
  end
  assign send_match__channel_s = ____state;
  assign send_match__channel_s_vld = p0_enable;
endmodule

module t;
   reg clk, rst, send_match__channel_s_rdy, send_match__channel_s, send_match__channel_s_vld;
   send_match sm_i(.clk(clk), .rst(rst),
                   .send_match__channel_s_rdy(send_match__channel_s_rdy),
                   .send_match__channel_s(send_match__channel_s),
                   .send_match__channel_s_vld(send_match__channel_s_vld));
   initial begin 
      rst = 1;
      clk = 0;
      send_match__channel_s_rdy = 0;
      $dumpfile("send_match.vcd");
      $dumpvars();
   end

   always #1 clk <= ~clk;
   assign #2 rst = 0;
   always #2 send_match__channel_s_rdy <= 1;
   initial #1000 $finish;
   always @(posedge clk) begin
      $display("valid: ", send_match__channel_s_vld, ", data: ", send_match__channel_s);
   end
endmodule
