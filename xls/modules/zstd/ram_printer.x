import std;
import xls.examples.ram;

enum RamPrinterStatus : u2 {
    IDLE = 0,
    BUSY = 1,
}

struct RamPrinterState<ADDR_WIDTH: u32> { status: RamPrinterStatus, addr: bits[ADDR_WIDTH] }

proc RamPrinter<DATA_WIDTH: u32, SIZE: u32, NUM_PARTITIONS: u32, ADDR_WIDTH: u32, NUM_MEMORIES: u32>
{
    print_r: chan<()> in;
    finish_s: chan<()> out;
    rd_req_s: chan<ram::ReadReq<ADDR_WIDTH, NUM_PARTITIONS>>[NUM_MEMORIES] out;
    rd_resp_r: chan<ram::ReadResp<DATA_WIDTH>>[NUM_MEMORIES] in;

    config(print_r: chan<()> in, finish_s: chan<()> out,
           rd_req_s: chan<ram::ReadReq<ADDR_WIDTH, NUM_PARTITIONS>>[NUM_MEMORIES] out,
           rd_resp_r: chan<ram::ReadResp<DATA_WIDTH>>[NUM_MEMORIES] in) {
        (print_r, finish_s, rd_req_s, rd_resp_r)
    }

    init { RamPrinterState { status: RamPrinterStatus::IDLE, addr: bits[ADDR_WIDTH]:0 } }

    next(tok: token, state: RamPrinterState) {
        let is_idle = state.status == RamPrinterStatus::IDLE;
        let (tok, _) = recv_if(tok, print_r, is_idle, ());

        let (tok, row) = for (i, (tok, row)): (u32, (token, bits[DATA_WIDTH][NUM_MEMORIES])) in
            range(u32:0, NUM_MEMORIES) {
            let tok = send(tok, rd_req_s[i], ram::ReadWordReq<NUM_PARTITIONS>(state.addr));
            let (tok, resp) = recv(tok, rd_resp_r[i]);
            let row = update(row, i, resp.data);
            (tok, row)
        }((tok, bits[DATA_WIDTH][NUM_MEMORIES]:[bits[DATA_WIDTH]:0, ...]));

        let is_start = state.addr == bits[ADDR_WIDTH]:0;
        let is_last = state.addr == (SIZE - u32:1) as bits[ADDR_WIDTH];

        if is_start { trace_fmt!(" ========= RAM content ========= "); } else {  };
        trace_fmt!(" {}:	{:x} ", state.addr, array_rev(row));

        let tok = send_if(tok, finish_s, is_last, ());

        if is_last {
            RamPrinterState { addr: bits[ADDR_WIDTH]:0, status: RamPrinterStatus::IDLE }
        } else {
            RamPrinterState {
                addr: state.addr + bits[ADDR_WIDTH]:1, status: RamPrinterStatus::BUSY
            }
        }
    }
}

const TEST_NUM_MEMORIES = u32:8;
const TEST_SIZE = u32:10;
const TEST_DATA_WIDTH = u32:8;
const TEST_WORD_PARTITION_SIZE = u32:1;
const TEST_NUM_PARTITIONS = ram::num_partitions(TEST_WORD_PARTITION_SIZE, TEST_DATA_WIDTH);
const TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR = ram::SimultaneousReadWriteBehavior::READ_BEFORE_WRITE;
const TEST_ADDR_WIDTH = std::clog2(TEST_SIZE);
const TEST_INITIALIZED = true;

type TestAddr = uN[TEST_ADDR_WIDTH];
type TestData = uN[TEST_DATA_WIDTH];

fn TestWriteWordReq
    (addr: TestAddr, data: TestData)
    -> ram::WriteReq<TEST_ADDR_WIDTH, TEST_DATA_WIDTH, TEST_NUM_PARTITIONS> {
    ram::WriteWordReq<TEST_NUM_PARTITIONS>(addr, data)
}

fn TestReadWordReq(addr: TestAddr) -> ram::ReadReq<TEST_ADDR_WIDTH, TEST_NUM_PARTITIONS> {
    ram::ReadWordReq<TEST_NUM_PARTITIONS>(addr)
}

#[test_proc]
proc RamPrinterTest {
    terminator: chan<bool> out;
    rd_req_s: chan<ram::ReadReq<TEST_ADDR_WIDTH, TEST_NUM_PARTITIONS>>[TEST_NUM_MEMORIES] out;
    rd_resp_r: chan<ram::ReadResp<TEST_DATA_WIDTH>>[TEST_NUM_MEMORIES] in;
    wr_req_s: chan<ram::WriteReq<TEST_ADDR_WIDTH, TEST_DATA_WIDTH, TEST_NUM_PARTITIONS>>[TEST_NUM_MEMORIES] out;
    wr_resp_r: chan<ram::WriteResp>[TEST_NUM_MEMORIES] in;
    print_s: chan<()> out;
    finish_r: chan<()> in;

    config(terminator: chan<bool> out) {
        let (rd_req_s, rd_req_r) =
            chan<ram::ReadReq<TEST_ADDR_WIDTH, TEST_NUM_PARTITIONS>>[TEST_NUM_MEMORIES];
        let (rd_resp_s, rd_resp_r) = chan<ram::ReadResp<TEST_DATA_WIDTH>>[TEST_NUM_MEMORIES];
        let (wr_req_s, wr_req_r) = chan<ram::WriteReq<TEST_ADDR_WIDTH, TEST_DATA_WIDTH, TEST_NUM_PARTITIONS>>[TEST_NUM_MEMORIES];
        let (wr_resp_s, wr_resp_r) = chan<ram::WriteResp>[TEST_NUM_MEMORIES];
        let (print_s, print_r) = chan<()>;
        let (finish_s, finish_r) = chan<()>;

        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[0], rd_resp_s[0], wr_req_r[0], wr_resp_s[0]);
        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[1], rd_resp_s[1], wr_req_r[1], wr_resp_s[1]);
        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[2], rd_resp_s[2], wr_req_r[2], wr_resp_s[2]);
        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[3], rd_resp_s[3], wr_req_r[3], wr_resp_s[3]);
        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[4], rd_resp_s[4], wr_req_r[4], wr_resp_s[4]);
        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[5], rd_resp_s[5], wr_req_r[5], wr_resp_s[5]);
        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[6], rd_resp_s[6], wr_req_r[6], wr_resp_s[6]);
        spawn ram::RamModel<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_WORD_PARTITION_SIZE, TEST_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_INITIALIZED>(
            rd_req_r[7], rd_resp_s[7], wr_req_r[7], wr_resp_s[7]);

        spawn RamPrinter<
            TEST_DATA_WIDTH, TEST_SIZE, TEST_NUM_PARTITIONS, TEST_ADDR_WIDTH, TEST_NUM_MEMORIES>(
            print_r, finish_s, rd_req_s, rd_resp_r);

        (terminator, rd_req_s, rd_resp_r, wr_req_s, wr_resp_r, print_s, finish_r)
    }

    init {  }

    next(tok: token, state: ()) {
        let tok = send(tok, wr_req_s[0], TestWriteWordReq(TestAddr:2, TestData:0x10));
        let tok = send(tok, wr_req_s[1], TestWriteWordReq(TestAddr:2, TestData:0x20));
        let tok = send(tok, wr_req_s[2], TestWriteWordReq(TestAddr:2, TestData:0x30));
        let tok = send(tok, wr_req_s[3], TestWriteWordReq(TestAddr:2, TestData:0x40));
        let tok = send(tok, wr_req_s[4], TestWriteWordReq(TestAddr:2, TestData:0x50));
        let tok = send(tok, wr_req_s[5], TestWriteWordReq(TestAddr:2, TestData:0x60));
        let tok = send(tok, wr_req_s[6], TestWriteWordReq(TestAddr:2, TestData:0x70));
        let tok = send(tok, wr_req_s[7], TestWriteWordReq(TestAddr:2, TestData:0x80));
        let tok = send(tok, print_s, ());
        let (tok, _) = recv(tok, finish_r);
        let tok = send(tok, terminator, true);
    }
}
