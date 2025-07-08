module ram_1r1w_delayed_wrapper #(
    parameter DATA_WIDTH     = 32,
    parameter SIZE           = 1024,
    parameter NUM_PARTITIONS = 1,
    parameter ADDR_WIDTH     = $clog2(SIZE),
    parameter INIT_FILE      = "",
    parameter READ_LATENCY   = 5,
    parameter WRITE_LATENCY  = 5
)(
    input  wire clk,
    input  wire rst,

    input  wire [DATA_WIDTH-1:0]     wr_data,
    input  wire [ADDR_WIDTH-1:0]     wr_addr,
    input  wire                      wr_en,
    input  wire [NUM_PARTITIONS-1:0] wr_mask,

    output reg  [DATA_WIDTH-1:0]     rd_data,
    input  wire [ADDR_WIDTH-1:0]     rd_addr,
    input  wire                      rd_en,
    input  wire [NUM_PARTITIONS-1:0] rd_mask
);

    localparam INTERNAL_WRITE_LATENCY = WRITE_LATENCY-1;
    localparam INTERNAL_READ_LATENCY = READ_LATENCY-1;

    reg [INTERNAL_WRITE_LATENCY-1:0][DATA_WIDTH-1:0]         wr_data_pipe;
    reg [INTERNAL_WRITE_LATENCY-1:0][ADDR_WIDTH-1:0]         wr_addr_pipe;
    reg [INTERNAL_WRITE_LATENCY-1:0][NUM_PARTITIONS-1:0]     wr_mask_pipe;
    reg [INTERNAL_WRITE_LATENCY-1:0]                         wr_en_pipe;

    reg [INTERNAL_READ_LATENCY-1:0][ADDR_WIDTH-1:0]          rd_addr_pipe;
    reg [INTERNAL_READ_LATENCY-1:0][NUM_PARTITIONS-1:0]      rd_mask_pipe;
    reg [INTERNAL_READ_LATENCY-1:0]                          rd_en_pipe;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < INTERNAL_WRITE_LATENCY; i = i + 1) begin
                wr_data_pipe[i] <= 0;
                wr_addr_pipe[i] <= 0;
                wr_mask_pipe[i] <= 0;
                wr_en_pipe[i]   <= 0;
            end
            for (i = 0; i < INTERNAL_READ_LATENCY; i = i + 1) begin
                rd_addr_pipe[i] <= 0;
                rd_mask_pipe[i] <= 0;
                rd_en_pipe[i]   <= 0;
            end
        end else begin
            wr_data_pipe[0] <= wr_data;
            wr_addr_pipe[0] <= wr_addr;
            wr_mask_pipe[0] <= wr_mask;
            wr_en_pipe[0]   <= wr_en;
            for (i = 1; i < INTERNAL_WRITE_LATENCY; i = i + 1) begin
                wr_data_pipe[i] <= wr_data_pipe[i-1];
                wr_addr_pipe[i] <= wr_addr_pipe[i-1];
                wr_mask_pipe[i] <= wr_mask_pipe[i-1];
                wr_en_pipe[i]   <= wr_en_pipe[i-1];
            end

            rd_addr_pipe[0] <= rd_addr;
            rd_mask_pipe[0] <= rd_mask;
            rd_en_pipe[0]   <= rd_en;
            for (i = 1; i < INTERNAL_READ_LATENCY; i = i + 1) begin
                rd_addr_pipe[i] <= rd_addr_pipe[i-1];
                rd_mask_pipe[i] <= rd_mask_pipe[i-1];
                rd_en_pipe[i]   <= rd_en_pipe[i-1];
            end
        end
    end

    ram_1r1w #(
        .DATA_WIDTH(DATA_WIDTH),
        .SIZE(SIZE),
        .NUM_PARTITIONS(NUM_PARTITIONS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE(INIT_FILE)
    ) ram_core (
        .clk(clk),
        .rst(rst),
        .wr_data(wr_data_pipe[INTERNAL_WRITE_LATENCY-1]),
        .wr_addr(wr_addr_pipe[INTERNAL_WRITE_LATENCY-1]),
        .wr_en(wr_en_pipe[INTERNAL_WRITE_LATENCY-1]),
        .wr_mask(wr_mask_pipe[INTERNAL_WRITE_LATENCY-1]),
        .rd_data(rd_data),
        .rd_addr(rd_addr_pipe[INTERNAL_READ_LATENCY-1]),
        .rd_en(rd_en_pipe[INTERNAL_READ_LATENCY-1]),
        .rd_mask(rd_mask_pipe[INTERNAL_READ_LATENCY-1])
    );

endmodule
