// Copyright 2024 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`default_nettype none

module zstd_dec_wrapper #(
    parameter AXI_DATA_W  = 32,
    parameter AXI_ADDR_W  = 16,
    parameter AXI_ID_W    = 4,
    parameter AXI_STRB_W  = 4,
    parameter AWUSER_WIDTH = 1,
    parameter WUSER_WIDTH = 1,
    parameter BUSER_WIDTH = 1,
    parameter ARUSER_WIDTH = 1,
    parameter RUSER_WIDTH = 1,
    parameter OUTPUT_WIDTH = 97
) (
    input wire clk,
    input wire rst,

    // AXI Master interface for the memory connection
    output wire [AXI_ID_W-1:0]      memory_axi_aw_awid,
    output wire [AXI_ADDR_W-1:0]    memory_axi_aw_awaddr,
    output wire [7:0]               memory_axi_aw_awlen,
    output wire [2:0]               memory_axi_aw_awsize,
    output wire [1:0]               memory_axi_aw_awburst,
    output wire                     memory_axi_aw_awlock,
    output wire [3:0]               memory_axi_aw_awcache,
    output wire [2:0]               memory_axi_aw_awprot,
    output wire [3:0]               memory_axi_aw_awqos,
    output wire [3:0]               memory_axi_aw_awregion,
    output wire [AWUSER_WIDTH-1:0]  memory_axi_aw_awuser,
    output wire                     memory_axi_aw_awvalid,
    input  wire                     memory_axi_aw_awready,
    output wire [AXI_DATA_W-1:0]    memory_axi_w_wdata,
    output wire [AXI_STRB_W-1:0]    memory_axi_w_wstrb,
    output wire                     memory_axi_w_wlast,
    output wire [WUSER_WIDTH-1:0]   memory_axi_w_wuser,
    output wire                     memory_axi_w_wvalid,
    input  wire                     memory_axi_w_wready,
    input  wire [AXI_ID_W-1:0]      memory_axi_b_bid,
    input  wire [2:0]               memory_axi_b_bresp,
    input  wire [BUSER_WIDTH-1:0]   memory_axi_b_buser,
    input  wire                     memory_axi_b_bvalid,
    output wire                     memory_axi_b_bready,
    output wire [AXI_ID_W-1:0]      memory_axi_ar_arid,
    output wire [AXI_ADDR_W-1:0]    memory_axi_ar_araddr,
    output wire [7:0]               memory_axi_ar_arlen,
    output wire [2:0]               memory_axi_ar_arsize,
    output wire [1:0]               memory_axi_ar_arburst,
    output wire                     memory_axi_ar_arlock,
    output wire [3:0]               memory_axi_ar_arcache,
    output wire [2:0]               memory_axi_ar_arprot,
    output wire [3:0]               memory_axi_ar_arqos,
    output wire [3:0]               memory_axi_ar_arregion,
    output wire [ARUSER_WIDTH-1:0]  memory_axi_ar_aruser,
    output wire                     memory_axi_ar_arvalid,
    input  wire                     memory_axi_ar_arready,
    input  wire [AXI_ID_W-1:0]      memory_axi_r_rid,
    input  wire [AXI_DATA_W-1:0]    memory_axi_r_rdata,
    input  wire [2:0]               memory_axi_r_rresp,
    input  wire                     memory_axi_r_rlast,
    input  wire [RUSER_WIDTH-1:0]   memory_axi_r_ruser,
    input  wire                     memory_axi_r_rvalid,
    output wire                     memory_axi_r_rready,

    // AXI Slave interface for the CSR access
    input wire [AXI_ID_W-1:0]       csr_axi_aw_awid,
    input wire [AXI_ADDR_W-1:0]     csr_axi_aw_awaddr,
    input wire [7:0]                csr_axi_aw_awlen,
    input wire [2:0]                csr_axi_aw_awsize,
    input wire [1:0]                csr_axi_aw_awburst,
    input wire                      csr_axi_aw_awlock,
    input wire [3:0]                csr_axi_aw_awcache,
    input wire [2:0]                csr_axi_aw_awprot,
    input wire [3:0]                csr_axi_aw_awqos,
    input wire [3:0]                csr_axi_aw_awregion,
    input wire [AWUSER_WIDTH-1:0]   csr_axi_aw_awuser,
    input wire                      csr_axi_aw_awvalid,
    output wire                     csr_axi_aw_awready,
    input wire [AXI_DATA_W-1:0]     csr_axi_w_wdata,
    input wire [AXI_STRB_W-1:0]     csr_axi_w_wstrb,
    input wire                      csr_axi_w_wlast,
    input wire [WUSER_WIDTH-1:0]    csr_axi_w_wuser,
    input wire                      csr_axi_w_wvalid,
    output wire                     csr_axi_w_wready,
    output wire [AXI_ID_W-1:0]      csr_axi_b_bid,
    output wire [2:0]               csr_axi_b_bresp,
    output wire [BUSER_WIDTH-1:0]   csr_axi_b_buser,
    output wire                     csr_axi_b_bvalid,
    input wire                      csr_axi_b_bready,
    input wire [AXI_ID_W-1:0]       csr_axi_ar_arid,
    input wire [AXI_ADDR_W-1:0]     csr_axi_ar_araddr,
    input wire [7:0]                csr_axi_ar_arlen,
    input wire [2:0]                csr_axi_ar_arsize,
    input wire [1:0]                csr_axi_ar_arburst,
    input wire                      csr_axi_ar_arlock,
    input wire [3:0]                csr_axi_ar_arcache,
    input wire [2:0]                csr_axi_ar_arprot,
    input wire [3:0]                csr_axi_ar_arqos,
    input wire [3:0]                csr_axi_ar_arregion,
    input wire [ARUSER_WIDTH-1:0]   csr_axi_ar_aruser,
    input wire                      csr_axi_ar_arvalid,
    output wire                     csr_axi_ar_arready,
    output wire [AXI_ID_W-1:0]      csr_axi_r_rid,
    output wire [AXI_DATA_W-1:0]    csr_axi_r_rdata,
    output wire [2:0]               csr_axi_r_rresp,
    output wire                     csr_axi_r_rlast,
    output wire [RUSER_WIDTH-1:0]   csr_axi_r_ruser,
    output wire                     csr_axi_r_rvalid,
    input wire                      csr_axi_r_rready,

    output wire                     notify_data,
    output wire                     notify_vld,
    input  wire                     notify_rdy,

    output wire [OUTPUT_WIDTH-1:0]  output_data,
    output wire                     output_vld,
    input  wire                     output_rdy
);

  /*
   * MemReader AXI interfaces
   */
  // RawBlockDecoder
  wire                  raw_block_decoder_axi_ar_arvalid;
  wire                  raw_block_decoder_axi_ar_arready;
  wire [  AXI_ID_W-1:0] raw_block_decoder_axi_ar_arid;
  wire [AXI_ADDR_W-1:0] raw_block_decoder_axi_ar_araddr;
  wire [           3:0] raw_block_decoder_axi_ar_arregion;
  wire [           7:0] raw_block_decoder_axi_ar_arlen;
  wire [           2:0] raw_block_decoder_axi_ar_arsize;
  wire [           1:0] raw_block_decoder_axi_ar_arburst;
  wire [           3:0] raw_block_decoder_axi_ar_arcache;
  wire [           2:0] raw_block_decoder_axi_ar_arprot;
  wire [           3:0] raw_block_decoder_axi_ar_arqos;

  wire                  raw_block_decoder_axi_r_rvalid;
  wire                  raw_block_decoder_axi_r_rready;
  wire [  AXI_ID_W-1:0] raw_block_decoder_axi_r_rid;
  wire [AXI_DATA_W-1:0] raw_block_decoder_axi_r_rdata;
  wire [           2:0] raw_block_decoder_axi_r_rresp;
  wire                  raw_block_decoder_axi_r_rlast;


  // RleBlockDecoder
  wire                  rle_block_decoder_axi_ar_arvalid;
  wire                  rle_block_decoder_axi_ar_arready;
  wire [  AXI_ID_W-1:0] rle_block_decoder_axi_ar_arid;
  wire [AXI_ADDR_W-1:0] rle_block_decoder_axi_ar_araddr;
  wire [           3:0] rle_block_decoder_axi_ar_arregion;
  wire [           7:0] rle_block_decoder_axi_ar_arlen;
  wire [           2:0] rle_block_decoder_axi_ar_arsize;
  wire [           1:0] rle_block_decoder_axi_ar_arburst;
  wire [           3:0] rle_block_decoder_axi_ar_arcache;
  wire [           2:0] rle_block_decoder_axi_ar_arprot;
  wire [           3:0] rle_block_decoder_axi_ar_arqos;

  wire                  rle_block_decoder_axi_r_rvalid;
  wire                  rle_block_decoder_axi_r_rready;
  wire [  AXI_ID_W-1:0] rle_block_decoder_axi_r_rid;
  wire [AXI_DATA_W-1:0] rle_block_decoder_axi_r_rdata;
  wire [           2:0] rle_block_decoder_axi_r_rresp;
  wire                  rle_block_decoder_axi_r_rlast;


  // BlockHeaderDecoder
  wire                  block_header_decoder_axi_ar_arvalid;
  wire                  block_header_decoder_axi_ar_arready;
  wire [  AXI_ID_W-1:0] block_header_decoder_axi_ar_arid;
  wire [AXI_ADDR_W-1:0] block_header_decoder_axi_ar_araddr;
  wire [           3:0] block_header_decoder_axi_ar_arregion;
  wire [           7:0] block_header_decoder_axi_ar_arlen;
  wire [           2:0] block_header_decoder_axi_ar_arsize;
  wire [           1:0] block_header_decoder_axi_ar_arburst;
  wire [           3:0] block_header_decoder_axi_ar_arcache;
  wire [           2:0] block_header_decoder_axi_ar_arprot;
  wire [           3:0] block_header_decoder_axi_ar_arqos;

  wire                  block_header_decoder_axi_r_rvalid;
  wire                  block_header_decoder_axi_r_rready;
  wire [  AXI_ID_W-1:0] block_header_decoder_axi_r_rid;
  wire [AXI_DATA_W-1:0] block_header_decoder_axi_r_rdata;
  wire [           2:0] block_header_decoder_axi_r_rresp;
  wire                  block_header_decoder_axi_r_rlast;


  // FrameHeaderDecoder
  wire                  frame_header_decoder_axi_ar_arvalid;
  wire                  frame_header_decoder_axi_ar_arready;
  wire [  AXI_ID_W-1:0] frame_header_decoder_axi_ar_arid;
  wire [AXI_ADDR_W-1:0] frame_header_decoder_axi_ar_araddr;
  wire [           3:0] frame_header_decoder_axi_ar_arregion;
  wire [           7:0] frame_header_decoder_axi_ar_arlen;
  wire [           2:0] frame_header_decoder_axi_ar_arsize;
  wire [           1:0] frame_header_decoder_axi_ar_arburst;
  wire [           3:0] frame_header_decoder_axi_ar_arcache;
  wire [           2:0] frame_header_decoder_axi_ar_arprot;
  wire [           3:0] frame_header_decoder_axi_ar_arqos;

  wire                  frame_header_decoder_axi_r_rvalid;
  wire                  frame_header_decoder_axi_r_rready;
  wire [  AXI_ID_W-1:0] frame_header_decoder_axi_r_rid;
  wire [AXI_DATA_W-1:0] frame_header_decoder_axi_r_rdata;
  wire [           2:0] frame_header_decoder_axi_r_rresp;
  wire                  frame_header_decoder_axi_r_rlast;


  /*
   * MemWriter AXI interfaces
   */

  // SequenceExecutor
  wire [  AXI_ID_W-1:0] sequence_executor_axi_aw_awid;
  wire [AXI_ADDR_W-1:0] sequence_executor_axi_aw_awaddr;
  wire [           2:0] sequence_executor_axi_aw_awsize;
  wire [           7:0] sequence_executor_axi_aw_awlen;
  wire [           1:0] sequence_executor_axi_aw_awburst;
  wire                  sequence_executor_axi_aw_awvalid;
  wire                  sequence_executor_axi_aw_awready;

  wire [AXI_DATA_W-1:0] sequence_executor_axi_w_wdata;
  wire [AXI_STRB_W-1:0] sequence_executor_axi_w_wstrb;
  wire                  sequence_executor_axi_w_wlast;
  wire                  sequence_executor_axi_w_wvalid;
  wire                  sequence_executor_axi_w_wready;

  wire [  AXI_ID_W-1:0] sequence_executor_axi_b_bid;
  wire [           2:0] sequence_executor_axi_b_bresp;
  wire                  sequence_executor_axi_b_bvalid;
  wire                  sequence_executor_axi_b_bready;

  /*
   * XLS Channels representing AXI interfaces
   */

  // CSR
  wire [32:0] dec__csr_axi_aw;
  wire dec__csr_axi_aw_rdy;
  wire dec__csr_axi_aw_vld;
  wire [36:0] dec__csr_axi_w;
  wire dec__csr_axi_w_rdy;
  wire dec__csr_axi_w_vld;
  wire [6:0] dec__csr_axi_b;
  wire dec__csr_axi_b_rdy;
  wire dec__csr_axi_b_vld;
  wire [47:0] dec__csr_axi_ar;
  wire dec__csr_axi_ar_rdy;
  wire dec__csr_axi_ar_vld;
  wire [39:0] dec__csr_axi_r;
  wire dec__csr_axi_r_rdy;
  wire dec__csr_axi_r_vld;

  // Frame Header Decoder
  wire [47:0] dec__fh_axi_ar;
  wire dec__fh_axi_ar_rdy;
  wire dec__fh_axi_ar_vld;
  wire [39:0] dec__fh_axi_r;
  wire dec__fh_axi_r_rdy;
  wire dec__fh_axi_r_vld;

  // Block Header Decoder
  wire [47:0] dec__bh_axi_ar;
  wire dec__bh_axi_ar_rdy;
  wire dec__bh_axi_ar_vld;
  wire [39:0] dec__bh_axi_r;
  wire dec__bh_axi_r_rdy;
  wire dec__bh_axi_r_vld;

  // Raw Block Decoder
  wire [47:0] dec__raw_axi_ar;
  wire dec__raw_axi_ar_rdy;
  wire dec__raw_axi_ar_vld;
  wire [39:0] dec__raw_axi_r;
  wire dec__raw_axi_r_rdy;
  wire dec__raw_axi_r_vld;

  // RLE Block Decoder
  wire [47:0] dec__rle_axi_ar;
  wire dec__rle_axi_ar_rdy;
  wire dec__rle_axi_ar_vld;
  wire [39:0] dec__rle_axi_r;
  wire dec__rle_axi_r_rdy;
  wire dec__rle_axi_r_vld;

  /*
   * Mapping XLS Channels to AXI channels fields
   */

  // CSR
  assign dec__csr_axi_aw = {
      csr_axi_aw_awid,
      csr_axi_aw_awaddr,
      csr_axi_aw_awsize,
      csr_axi_aw_awlen,
      csr_axi_aw_awburst
      };
  assign  dec__csr_axi_aw_vld = csr_axi_aw_awvalid;
  assign csr_axi_aw_awready = dec__csr_axi_aw_rdy;
  assign dec__csr_axi_w = {
      csr_axi_w_wdata,
      csr_axi_w_wstrb,
      csr_axi_w_wlast
      };
  assign dec__csr_axi_w_vld = csr_axi_w_wvalid;
  assign csr_axi_w_wready = dec__csr_axi_w_rdy;
  assign {
      csr_axi_b_bresp,
      csr_axi_b_bid
      } = dec__csr_axi_b;
  assign csr_axi_b_bvalid = dec__csr_axi_b_vld;
  assign dec__csr_axi_b_rdy = csr_axi_b_bready;
  assign dec__csr_axi_ar = {
      csr_axi_ar_arid,
      csr_axi_ar_araddr,
      csr_axi_ar_arregion,
      csr_axi_ar_arlen,
      csr_axi_ar_arsize,
      csr_axi_ar_arburst,
      csr_axi_ar_arcache,
      csr_axi_ar_arprot,
      csr_axi_ar_arqos
      };
  assign dec__csr_axi_ar_vld = csr_axi_ar_arvalid;
  assign csr_axi_ar_arready = dec__csr_axi_ar_rdy;
  assign {
      csr_axi_r_rid,
      csr_axi_r_rdata,
      csr_axi_r_rresp,
      csr_axi_r_rlast
      } = dec__csr_axi_r;
  assign csr_axi_r_rvalid = dec__csr_axi_r_vld;
  assign dec__csr_axi_r_rdy = csr_axi_r_rready;

  // Frame Header Decoder
  assign {
      frame_header_decoder_axi_ar_arid,
      frame_header_decoder_axi_ar_araddr,
      frame_header_decoder_axi_ar_arregion,
      frame_header_decoder_axi_ar_arlen,
      frame_header_decoder_axi_ar_arsize,
      frame_header_decoder_axi_ar_arburst,
      frame_header_decoder_axi_ar_arcache,
      frame_header_decoder_axi_ar_arprot,
      frame_header_decoder_axi_ar_arqos
      } = dec__fh_axi_ar;
  assign frame_header_decoder_axi_ar_arvalid = dec__fh_axi_ar_vld;
  assign dec__fh_axi_ar_rdy = frame_header_decoder_axi_ar_arready;
  assign dec__fh_axi_r = {
      frame_header_decoder_axi_r_rid,
      frame_header_decoder_axi_r_rdata,
      frame_header_decoder_axi_r_rresp,
      frame_header_decoder_axi_r_rlast};
  assign dec__fh_axi_r_vld = frame_header_decoder_axi_r_rvalid;
  assign frame_header_decoder_axi_r_rready = dec__fh_axi_r_rdy;

  // Block Header Decoder
  assign {
      block_header_decoder_axi_ar_arid,
      block_header_decoder_axi_ar_araddr,
      block_header_decoder_axi_ar_arregion,
      block_header_decoder_axi_ar_arlen,
      block_header_decoder_axi_ar_arsize,
      block_header_decoder_axi_ar_arburst,
      block_header_decoder_axi_ar_arcache,
      block_header_decoder_axi_ar_arprot,
      block_header_decoder_axi_ar_arqos
      } = dec__bh_axi_ar;
  assign block_header_decoder_axi_ar_arvalid = dec__bh_axi_ar_vld;
  assign dec__bh_axi_ar_rdy = block_header_decoder_axi_ar_arready;
  assign dec__bh_axi_r = {
      block_header_decoder_axi_r_rid,
      block_header_decoder_axi_r_rdata,
      block_header_decoder_axi_r_rresp,
      block_header_decoder_axi_r_rlast};
  assign dec__bh_axi_r_vld = block_header_decoder_axi_r_rvalid;
  assign block_header_decoder_axi_r_rready = dec__bh_axi_r_rdy;

  // Raw Block Decoder
  assign {
      raw_block_decoder_axi_ar_arid,
      raw_block_decoder_axi_ar_araddr,
      raw_block_decoder_axi_ar_arregion,
      raw_block_decoder_axi_ar_arlen,
      raw_block_decoder_axi_ar_arsize,
      raw_block_decoder_axi_ar_arburst,
      raw_block_decoder_axi_ar_arcache,
      raw_block_decoder_axi_ar_arprot,
      raw_block_decoder_axi_ar_arqos
      } = dec__raw_axi_ar;
  assign raw_block_decoder_axi_ar_arvalid = dec__raw_axi_ar_vld;
  assign dec__raw_axi_ar_rdy = raw_block_decoder_axi_ar_arready;
  assign dec__raw_axi_r = {
      raw_block_decoder_axi_r_rid,
      raw_block_decoder_axi_r_rdata,
      raw_block_decoder_axi_r_rresp,
      raw_block_decoder_axi_r_rlast};
  assign dec__raw_axi_r_vld = raw_block_decoder_axi_r_rvalid;
  assign raw_block_decoder_axi_r_rready = dec__raw_axi_r_rdy;

  // RLE Block Decoder
  assign {
      rle_block_decoder_axi_ar_arid,
      rle_block_decoder_axi_ar_araddr,
      rle_block_decoder_axi_ar_arregion,
      rle_block_decoder_axi_ar_arlen,
      rle_block_decoder_axi_ar_arsize,
      rle_block_decoder_axi_ar_arburst,
      rle_block_decoder_axi_ar_arcache,
      rle_block_decoder_axi_ar_arprot,
      rle_block_decoder_axi_ar_arqos
      } = dec__rle_axi_ar;
  assign rle_block_decoder_axi_ar_arvalid = dec__rle_axi_ar_vld;
  assign dec__rle_axi_ar_rdy = rle_block_decoder_axi_ar_arready;
  assign dec__rle_axi_r = {
      rle_block_decoder_axi_r_rid,
      rle_block_decoder_axi_r_rdata,
      rle_block_decoder_axi_r_rresp,
      rle_block_decoder_axi_r_rlast};
  assign dec__rle_axi_r_vld = rle_block_decoder_axi_r_rvalid;
  assign rle_block_decoder_axi_r_rready = dec__rle_axi_r_rdy;

assign csr_axi_b_buser = 1'b0;
assign csr_axi_r_ruser = 1'b0;
assign notify_data = notify_vld;

  /*
   * ZSTD Decoder instance
   */
  ZstdDecoder ZstdDecoder (
      .clk(clk),
      .rst(rst),

      // CSR Interface
      .dec__csr_axi_aw_r(dec__csr_axi_aw),
      .dec__csr_axi_aw_r_vld(dec__csr_axi_aw_vld),
      .dec__csr_axi_aw_r_rdy(dec__csr_axi_aw_rdy),
      .dec__csr_axi_w_r(dec__csr_axi_w),
      .dec__csr_axi_w_r_vld(dec__csr_axi_w_vld),
      .dec__csr_axi_w_r_rdy(dec__csr_axi_w_rdy),
      .dec__csr_axi_b_s(dec__csr_axi_b),
      .dec__csr_axi_b_s_vld(dec__csr_axi_b_vld),
      .dec__csr_axi_b_s_rdy(dec__csr_axi_b_rdy),
      .dec__csr_axi_ar_r(dec__csr_axi_ar),
      .dec__csr_axi_ar_r_vld(dec__csr_axi_ar_vld),
      .dec__csr_axi_ar_r_rdy(dec__csr_axi_ar_rdy),
      .dec__csr_axi_r_s(dec__csr_axi_r),
      .dec__csr_axi_r_s_vld(dec__csr_axi_r_vld),
      .dec__csr_axi_r_s_rdy(dec__csr_axi_r_rdy),

      // FrameHeaderDecoder
      .dec__fh_axi_ar_s(dec__fh_axi_ar),
      .dec__fh_axi_ar_s_vld(dec__fh_axi_ar_vld),
      .dec__fh_axi_ar_s_rdy(dec__fh_axi_ar_rdy),
      .dec__fh_axi_r_r(dec__fh_axi_r),
      .dec__fh_axi_r_r_vld(dec__fh_axi_r_vld),
      .dec__fh_axi_r_r_rdy(dec__fh_axi_r_rdy),

      // BlockHeaderDecoder
      .dec__bh_axi_ar_s(dec__bh_axi_ar),
      .dec__bh_axi_ar_s_vld(dec__bh_axi_ar_vld),
      .dec__bh_axi_ar_s_rdy(dec__bh_axi_ar_rdy),
      .dec__bh_axi_r_r(dec__bh_axi_r),
      .dec__bh_axi_r_r_vld(dec__bh_axi_r_vld),
      .dec__bh_axi_r_r_rdy(dec__bh_axi_r_rdy),

      // RawBlockDecoder
      .dec__raw_axi_ar_s(dec__raw_axi_ar),
      .dec__raw_axi_ar_s_vld(dec__raw_axi_ar_vld),
      .dec__raw_axi_ar_s_rdy(dec__raw_axi_ar_rdy),
      .dec__raw_axi_r_r(dec__raw_axi_r),
      .dec__raw_axi_r_r_vld(dec__raw_axi_r_vld),
      .dec__raw_axi_r_r_rdy(dec__raw_axi_r_rdy),

      // RleBlock decoder
      .dec__rle_axi_ar_s(dec__rle_axi_ar),
      .dec__rle_axi_ar_s_vld(dec__rle_axi_ar_vld),
      .dec__rle_axi_ar_s_rdy(dec__rle_axi_ar_rdy),
      .dec__rle_axi_r_r(dec__rle_axi_r),
      .dec__rle_axi_r_r_vld(dec__rle_axi_r_vld),
      .dec__rle_axi_r_r_rdy(dec__rle_axi_r_rdy),

      // Other ports
      .dec__notify_s_vld(notify_vld),
      .dec__notify_s_rdy(notify_rdy),
      .dec__output_s(output_data),
      .dec__output_s_vld(output_vld),
      .dec__output_s_rdy(output_rdy),

      .dec__ram_rd_req_0_s(),
      .dec__ram_rd_req_1_s(),
      .dec__ram_rd_req_2_s(),
      .dec__ram_rd_req_3_s(),
      .dec__ram_rd_req_4_s(),
      .dec__ram_rd_req_5_s(),
      .dec__ram_rd_req_6_s(),
      .dec__ram_rd_req_7_s(),
      .dec__ram_rd_req_0_s_vld(),
      .dec__ram_rd_req_1_s_vld(),
      .dec__ram_rd_req_2_s_vld(),
      .dec__ram_rd_req_3_s_vld(),
      .dec__ram_rd_req_4_s_vld(),
      .dec__ram_rd_req_5_s_vld(),
      .dec__ram_rd_req_6_s_vld(),
      .dec__ram_rd_req_7_s_vld(),
      .dec__ram_rd_req_0_s_rdy('1),
      .dec__ram_rd_req_1_s_rdy('1),
      .dec__ram_rd_req_2_s_rdy('1),
      .dec__ram_rd_req_3_s_rdy('1),
      .dec__ram_rd_req_4_s_rdy('1),
      .dec__ram_rd_req_5_s_rdy('1),
      .dec__ram_rd_req_6_s_rdy('1),
      .dec__ram_rd_req_7_s_rdy('1),

      .dec__ram_rd_resp_0_r('0),
      .dec__ram_rd_resp_1_r('0),
      .dec__ram_rd_resp_2_r('0),
      .dec__ram_rd_resp_3_r('0),
      .dec__ram_rd_resp_4_r('0),
      .dec__ram_rd_resp_5_r('0),
      .dec__ram_rd_resp_6_r('0),
      .dec__ram_rd_resp_7_r('0),
      .dec__ram_rd_resp_0_r_vld('1),
      .dec__ram_rd_resp_1_r_vld('1),
      .dec__ram_rd_resp_2_r_vld('1),
      .dec__ram_rd_resp_3_r_vld('1),
      .dec__ram_rd_resp_4_r_vld('1),
      .dec__ram_rd_resp_5_r_vld('1),
      .dec__ram_rd_resp_6_r_vld('1),
      .dec__ram_rd_resp_7_r_vld('1),
      .dec__ram_rd_resp_0_r_rdy(),
      .dec__ram_rd_resp_1_r_rdy(),
      .dec__ram_rd_resp_2_r_rdy(),
      .dec__ram_rd_resp_3_r_rdy(),
      .dec__ram_rd_resp_4_r_rdy(),
      .dec__ram_rd_resp_5_r_rdy(),
      .dec__ram_rd_resp_6_r_rdy(),
      .dec__ram_rd_resp_7_r_rdy(),

      .dec__ram_wr_req_0_s(),
      .dec__ram_wr_req_1_s(),
      .dec__ram_wr_req_2_s(),
      .dec__ram_wr_req_3_s(),
      .dec__ram_wr_req_4_s(),
      .dec__ram_wr_req_5_s(),
      .dec__ram_wr_req_6_s(),
      .dec__ram_wr_req_7_s(),
      .dec__ram_wr_req_0_s_vld(),
      .dec__ram_wr_req_1_s_vld(),
      .dec__ram_wr_req_2_s_vld(),
      .dec__ram_wr_req_3_s_vld(),
      .dec__ram_wr_req_4_s_vld(),
      .dec__ram_wr_req_5_s_vld(),
      .dec__ram_wr_req_6_s_vld(),
      .dec__ram_wr_req_7_s_vld(),
      .dec__ram_wr_req_0_s_rdy('1),
      .dec__ram_wr_req_1_s_rdy('1),
      .dec__ram_wr_req_2_s_rdy('1),
      .dec__ram_wr_req_3_s_rdy('1),
      .dec__ram_wr_req_4_s_rdy('1),
      .dec__ram_wr_req_5_s_rdy('1),
      .dec__ram_wr_req_6_s_rdy('1),
      .dec__ram_wr_req_7_s_rdy('1),

      .dec__ram_wr_resp_0_r_vld('1),
      .dec__ram_wr_resp_1_r_vld('1),
      .dec__ram_wr_resp_2_r_vld('1),
      .dec__ram_wr_resp_3_r_vld('1),
      .dec__ram_wr_resp_4_r_vld('1),
      .dec__ram_wr_resp_5_r_vld('1),
      .dec__ram_wr_resp_6_r_vld('1),
      .dec__ram_wr_resp_7_r_vld('1),
      .dec__ram_wr_resp_0_r_rdy(),
      .dec__ram_wr_resp_1_r_rdy(),
      .dec__ram_wr_resp_2_r_rdy(),
      .dec__ram_wr_resp_3_r_rdy(),
      .dec__ram_wr_resp_4_r_rdy(),
      .dec__ram_wr_resp_5_r_rdy(),
      .dec__ram_wr_resp_6_r_rdy(),
      .dec__ram_wr_resp_7_r_rdy()
  );

  assign frame_header_decoder_axi_r_rresp[2] = '0;
  assign block_header_decoder_axi_r_rresp[2] = '0;
  assign raw_block_decoder_axi_r_rresp[2] = '0;
  assign rle_block_decoder_axi_r_rresp[2] = '0;
  assign sequence_executor_axi_b_bresp[2] = '0;
  assign memory_axi_b_bresp[2] = '0;
  assign memory_axi_r_rresp[2] = '0;
  /*
   * AXI Interconnect
   */
  axi_interconnect_wrapper #(
      .DATA_WIDTH(AXI_DATA_W),
      .ADDR_WIDTH(AXI_ADDR_W),
      .M00_ADDR_WIDTH(AXI_ADDR_W),
      .M00_BASE_ADDR(32'd0),
      .STRB_WIDTH(AXI_STRB_W),
      .ID_WIDTH(AXI_ID_W)
  ) axi_memory_interconnect (
      .clk(clk),
      .rst(rst),

      /*
       * AXI slave interfaces
       */
      // FrameHeaderDecoder
      .s00_axi_awid('0),
      .s00_axi_awaddr('0),
      .s00_axi_awlen('0),
      .s00_axi_awsize('0),
      .s00_axi_awburst('0),
      .s00_axi_awlock('0),
      .s00_axi_awcache('0),
      .s00_axi_awprot('0),
      .s00_axi_awqos('0),
      .s00_axi_awuser('0),
      .s00_axi_awvalid('0),
      .s00_axi_awready(),
      .s00_axi_wdata('0),
      .s00_axi_wstrb('0),
      .s00_axi_wlast('0),
      .s00_axi_wuser('0),
      .s00_axi_wvalid(),
      .s00_axi_wready(),
      .s00_axi_bid(),
      .s00_axi_bresp(),
      .s00_axi_buser(),
      .s00_axi_bvalid(),
      .s00_axi_bready('0),
      .s00_axi_arid(frame_header_decoder_axi_ar_arid),
      .s00_axi_araddr(frame_header_decoder_axi_ar_araddr),
      .s00_axi_arlen(frame_header_decoder_axi_ar_arlen),
      .s00_axi_arsize(frame_header_decoder_axi_ar_arsize),
      .s00_axi_arburst(frame_header_decoder_axi_ar_arburst),
      .s00_axi_arlock('0),
      .s00_axi_arcache(frame_header_decoder_axi_ar_arcache),
      .s00_axi_arprot(frame_header_decoder_axi_ar_arprot),
      .s00_axi_arqos(frame_header_decoder_axi_ar_arqos),
      .s00_axi_aruser('0),
      .s00_axi_arvalid(frame_header_decoder_axi_ar_arvalid),
      .s00_axi_arready(frame_header_decoder_axi_ar_arready),
      .s00_axi_rid(frame_header_decoder_axi_r_rid),
      .s00_axi_rdata(frame_header_decoder_axi_r_rdata),
      .s00_axi_rresp(frame_header_decoder_axi_r_rresp[1:0]),
      .s00_axi_rlast(frame_header_decoder_axi_r_rlast),
      .s00_axi_ruser(),
      .s00_axi_rvalid(frame_header_decoder_axi_r_rvalid),
      .s00_axi_rready(frame_header_decoder_axi_r_rready),

      // BlockHeaderDecoder
      .s01_axi_awid('0),
      .s01_axi_awaddr('0),
      .s01_axi_awlen('0),
      .s01_axi_awsize('0),
      .s01_axi_awburst('0),
      .s01_axi_awlock('0),
      .s01_axi_awcache('0),
      .s01_axi_awprot('0),
      .s01_axi_awqos('0),
      .s01_axi_awuser('0),
      .s01_axi_awvalid('0),
      .s01_axi_awready(),
      .s01_axi_wdata('0),
      .s01_axi_wstrb('0),
      .s01_axi_wlast('0),
      .s01_axi_wuser('0),
      .s01_axi_wvalid(),
      .s01_axi_wready(),
      .s01_axi_bid(),
      .s01_axi_bresp(),
      .s01_axi_buser(),
      .s01_axi_bvalid(),
      .s01_axi_bready('0),
      .s01_axi_arid(block_header_decoder_axi_ar_arid),
      .s01_axi_araddr(block_header_decoder_axi_ar_araddr),
      .s01_axi_arlen(block_header_decoder_axi_ar_arlen),
      .s01_axi_arsize(block_header_decoder_axi_ar_arsize),
      .s01_axi_arburst(block_header_decoder_axi_ar_arburst),
      .s01_axi_arlock('0),
      .s01_axi_arcache(block_header_decoder_axi_ar_arcache),
      .s01_axi_arprot(block_header_decoder_axi_ar_arprot),
      .s01_axi_arqos(block_header_decoder_axi_ar_arqos),
      .s01_axi_aruser('0),
      .s01_axi_arvalid(block_header_decoder_axi_ar_arvalid),
      .s01_axi_arready(block_header_decoder_axi_ar_arready),
      .s01_axi_rid(block_header_decoder_axi_r_rid),
      .s01_axi_rdata(block_header_decoder_axi_r_rdata),
      .s01_axi_rresp(block_header_decoder_axi_r_rresp[1:0]),
      .s01_axi_rlast(block_header_decoder_axi_r_rlast),
      .s01_axi_ruser(),
      .s01_axi_rvalid(block_header_decoder_axi_r_rvalid),
      .s01_axi_rready(block_header_decoder_axi_r_rready),

      // RawBlockDecoder
      .s02_axi_awid('0),
      .s02_axi_awaddr('0),
      .s02_axi_awlen('0),
      .s02_axi_awsize('0),
      .s02_axi_awburst('0),
      .s02_axi_awlock('0),
      .s02_axi_awcache('0),
      .s02_axi_awprot('0),
      .s02_axi_awqos('0),
      .s02_axi_awuser('0),
      .s02_axi_awvalid('0),
      .s02_axi_awready(),
      .s02_axi_wdata('0),
      .s02_axi_wstrb('0),
      .s02_axi_wlast('0),
      .s02_axi_wuser('0),
      .s02_axi_wvalid(),
      .s02_axi_wready(),
      .s02_axi_bid(),
      .s02_axi_bresp(),
      .s02_axi_buser(),
      .s02_axi_bvalid(),
      .s02_axi_bready('0),
      .s02_axi_arid(raw_block_decoder_axi_ar_arid),
      .s02_axi_araddr(raw_block_decoder_axi_ar_araddr),
      .s02_axi_arlen(raw_block_decoder_axi_ar_arlen),
      .s02_axi_arsize(raw_block_decoder_axi_ar_arsize),
      .s02_axi_arburst(raw_block_decoder_axi_ar_arburst),
      .s02_axi_arlock('0),
      .s02_axi_arcache(raw_block_decoder_axi_ar_arcache),
      .s02_axi_arprot(raw_block_decoder_axi_ar_arprot),
      .s02_axi_arqos(raw_block_decoder_axi_ar_arqos),
      .s02_axi_aruser('0),
      .s02_axi_arvalid(raw_block_decoder_axi_ar_arvalid),
      .s02_axi_arready(raw_block_decoder_axi_ar_arready),
      .s02_axi_rid(raw_block_decoder_axi_r_rid),
      .s02_axi_rdata(raw_block_decoder_axi_r_rdata),
      .s02_axi_rresp(raw_block_decoder_axi_r_rresp[1:0]),
      .s02_axi_rlast(raw_block_decoder_axi_r_rlast),
      .s02_axi_ruser(),
      .s02_axi_rvalid(raw_block_decoder_axi_r_rvalid),
      .s02_axi_rready(raw_block_decoder_axi_r_rready),

      // RleBlockDecoder
      .s03_axi_awid('0),
      .s03_axi_awaddr('0),
      .s03_axi_awlen('0),
      .s03_axi_awsize('0),
      .s03_axi_awburst('0),
      .s03_axi_awlock('0),
      .s03_axi_awcache('0),
      .s03_axi_awprot('0),
      .s03_axi_awqos('0),
      .s03_axi_awuser('0),
      .s03_axi_awvalid('0),
      .s03_axi_awready(),
      .s03_axi_wdata('0),
      .s03_axi_wstrb('0),
      .s03_axi_wlast('0),
      .s03_axi_wuser('0),
      .s03_axi_wvalid(),
      .s03_axi_wready(),
      .s03_axi_bid(),
      .s03_axi_bresp(),
      .s03_axi_buser(),
      .s03_axi_bvalid(),
      .s03_axi_bready('0),
      .s03_axi_arid(rle_block_decoder_axi_ar_arid),
      .s03_axi_araddr(rle_block_decoder_axi_ar_araddr),
      .s03_axi_arlen(rle_block_decoder_axi_ar_arlen),
      .s03_axi_arsize(rle_block_decoder_axi_ar_arsize),
      .s03_axi_arburst(rle_block_decoder_axi_ar_arburst),
      .s03_axi_arlock('0),
      .s03_axi_arcache(rle_block_decoder_axi_ar_arcache),
      .s03_axi_arprot(rle_block_decoder_axi_ar_arprot),
      .s03_axi_arqos(rle_block_decoder_axi_ar_arqos),
      .s03_axi_aruser('0),
      .s03_axi_arvalid(rle_block_decoder_axi_ar_arvalid),
      .s03_axi_arready(rle_block_decoder_axi_ar_arready),
      .s03_axi_rid(rle_block_decoder_axi_r_rid),
      .s03_axi_rdata(rle_block_decoder_axi_r_rdata),
      .s03_axi_rresp(rle_block_decoder_axi_r_rresp[1:0]),
      .s03_axi_rlast(rle_block_decoder_axi_r_rlast),
      .s03_axi_ruser(),
      .s03_axi_rvalid(rle_block_decoder_axi_r_rvalid),
      .s03_axi_rready(rle_block_decoder_axi_r_rready),

      // SequenceExecutor
      .s04_axi_awid(sequence_executor_axi_aw_awid),
      .s04_axi_awaddr(sequence_executor_axi_aw_awaddr),
      .s04_axi_awlen(sequence_executor_axi_aw_awlen),
      .s04_axi_awsize(sequence_executor_axi_aw_awsize),
      .s04_axi_awburst(sequence_executor_axi_aw_awburst),
      .s04_axi_awlock('0),
      .s04_axi_awcache('0),
      .s04_axi_awprot('0),
      .s04_axi_awqos('0),
      .s04_axi_awuser('0),
      .s04_axi_awvalid(sequence_executor_axi_aw_awvalid),
      .s04_axi_awready(sequence_executor_axi_aw_awready),
      .s04_axi_wdata(sequence_executor_axi_w_wdata),
      .s04_axi_wstrb(sequence_executor_axi_w_wstrb),
      .s04_axi_wlast(sequence_executor_axi_w_wlast),
      .s04_axi_wuser('0),
      .s04_axi_wvalid(sequence_executor_axi_w_wvalid),
      .s04_axi_wready(sequence_executor_axi_w_wready),
      .s04_axi_bid(sequence_executor_axi_b_bid),
      .s04_axi_bresp(sequence_executor_axi_b_bresp[1:0]),
      .s04_axi_buser(),
      .s04_axi_bvalid(sequence_executor_axi_b_bvalid),
      .s04_axi_bready(sequence_executor_axi_b_bready),
      .s04_axi_arid('0),
      .s04_axi_araddr('0),
      .s04_axi_arlen('0),
      .s04_axi_arsize('0),
      .s04_axi_arburst('0),
      .s04_axi_arlock('0),
      .s04_axi_arcache('0),
      .s04_axi_arprot('0),
      .s04_axi_arqos('0),
      .s04_axi_aruser('0),
      .s04_axi_arvalid('0),
      .s04_axi_arready(),
      .s04_axi_rid(),
      .s04_axi_rdata(),
      .s04_axi_rresp(),
      .s04_axi_rlast(),
      .s04_axi_ruser(),
      .s04_axi_rvalid(),
      .s04_axi_rready('0),

      /*
       * AXI master interface
       */
      // Outside-facing AXI interface of the ZSTD Decoder
      .m00_axi_awid(memory_axi_aw_awid),
      .m00_axi_awaddr(memory_axi_aw_awaddr),
      .m00_axi_awlen(memory_axi_aw_awlen),
      .m00_axi_awsize(memory_axi_aw_awsize),
      .m00_axi_awburst(memory_axi_aw_awburst),
      .m00_axi_awlock(memory_axi_aw_awlock),
      .m00_axi_awcache(memory_axi_aw_awcache),
      .m00_axi_awprot(memory_axi_aw_awprot),
      .m00_axi_awqos(memory_axi_aw_awqos),
      .m00_axi_awregion(memory_axi_aw_awregion),
      .m00_axi_awuser(memory_axi_aw_awuser),
      .m00_axi_awvalid(memory_axi_aw_awvalid),
      .m00_axi_awready(memory_axi_aw_awready),
      .m00_axi_wdata(memory_axi_w_wdata),
      .m00_axi_wstrb(memory_axi_w_wstrb),
      .m00_axi_wlast(memory_axi_w_wlast),
      .m00_axi_wuser(memory_axi_w_wuser),
      .m00_axi_wvalid(memory_axi_w_wvalid),
      .m00_axi_wready(memory_axi_w_wready),
      .m00_axi_bid(memory_axi_b_bid),
      .m00_axi_bresp(memory_axi_b_bresp[1:0]),
      .m00_axi_buser(memory_axi_b_buser),
      .m00_axi_bvalid(memory_axi_b_bvalid),
      .m00_axi_bready(memory_axi_b_bready),
      .m00_axi_arid(memory_axi_ar_arid),
      .m00_axi_araddr(memory_axi_ar_araddr),
      .m00_axi_arlen(memory_axi_ar_arlen),
      .m00_axi_arsize(memory_axi_ar_arsize),
      .m00_axi_arburst(memory_axi_ar_arburst),
      .m00_axi_arlock(memory_axi_ar_arlock),
      .m00_axi_arcache(memory_axi_ar_arcache),
      .m00_axi_arprot(memory_axi_ar_arprot),
      .m00_axi_arqos(memory_axi_ar_arqos),
      .m00_axi_arregion(memory_axi_ar_arregion),
      .m00_axi_aruser(memory_axi_ar_aruser),
      .m00_axi_arvalid(memory_axi_ar_arvalid),
      .m00_axi_arready(memory_axi_ar_arready),
      .m00_axi_rid(memory_axi_r_rid),
      .m00_axi_rdata(memory_axi_r_rdata),
      .m00_axi_rresp(memory_axi_r_rresp[1:0]),
      .m00_axi_rlast(memory_axi_r_rlast),
      .m00_axi_ruser(memory_axi_r_ruser),
      .m00_axi_rvalid(memory_axi_r_rvalid),
      .m00_axi_rready(memory_axi_r_rready)
  );

endmodule : zstd_dec_wrapper
