import std

// Structure to preserve state of the RLEEnc for the next iteration
pub struct RLEEncState<SYMB_WIDTH: u32, CNT_WIDTH: u32> {
    prev_symb: bits[SYMB_WIDTH], // symbol obtained in the previous iteration
    prev_cnt: bits[CNT_WIDTH],   // symbol count from the previous iteration
}

// RLE Encoder implementation
pub proc RLEEnc<SYMB_WIDTH: u32, CNT_WIDTH: u32> {
    data_r: chan<bits[SYMB_WIDTH]> in;  // input with symbols
    cnt_s: chan<bits[CNT_WIDTH]> out;   // output with symbol count
    symb_s: chan<bits[SYMB_WIDTH]> out; // output with symbols

    init {(
        RLEEncState<SYMB_WIDTH, CNT_WIDTH> {
            prev_symb: bits[SYMB_WIDTH]:0,
            prev_cnt: bits[CNT_WIDTH]:0,
        }
    )}

    config (
        data_r: chan<bits[SYMB_WIDTH]> in,
        cnt_s: chan<bits[CNT_WIDTH]> out,
        symb_s: chan<bits[SYMB_WIDTH]> out
    ) {(data_r, cnt_s, symb_s)}

    next (tok: token, state: RLEEncState<SYMB_WIDTH, CNT_WIDTH>) {
        let (tok, symb) = recv(tok, data_r);

        let symb_differ = (state.prev_cnt != bits[CNT_WIDTH]:0) && (symb != state.prev_symb);
        let max_cnt = std::unsigned_max_value<CNT_WIDTH>();
        let overflow = state.prev_cnt == max_cnt;

        if (symb_differ || overflow) {
            let symb_tok = send(tok, symb_s, state.prev_symb);
            let cnt_tok = send(tok, cnt_s, state.prev_cnt);
            RLEEncState {
                prev_symb: symb,
                prev_cnt: bits[CNT_WIDTH]:1,
            }
        } else {
            RLEEncState {
                prev_symb: symb,
                prev_cnt: state.prev_cnt + bits[CNT_WIDTH]:1,
            }
        }
    }
}

// RLE Encoder specialization for codegen
proc RLEEnc32 {
    data_r: chan<bits[32]> in;  // input with symbols
    cnt_s: chan<bits[32]> out;  // output with symbol count
    symb_s: chan<bits[32]> out; // output with symbols

    init {()}

    config (
        data_r: chan<bits[32]> in,
        cnt_s: chan<bits[32]> out,
        symb_s: chan<bits[32]> out
    ) {
        spawn RLEEnc<u32:32, u32:32>(data_r, cnt_s, symb_s);
        (data_r, cnt_s, symb_s)
    }

    next (tok: token, state: ()) {
        ()
    }
}

// Tests

const TEST_SYMB_WIDTH = u32:32;
const TEST_CNT_WIDTH = u32:2;
const TEST_SYMB_CNT_LIMIT = u32:10;
const END_SYMB = u32:0x0;

const TEST_SEND_SYMB_LOOKUP = u32[21]:[
    0xA, 0xA, 0xA,
    0xB, 0xB,
    0x1,
    0xC, 0xC, 0xC, 0xC, 0xC, 0xC,
    0x3, 0x3, 0x3,
    0x2, 0x2,
    0x1,
    0x2,
    0x3,
    END_SYMB,
];

const TEST_RECV_SYMB_LOOKUP = bits[TEST_SYMB_WIDTH][10]:[
    0xA, 0xB, 0x1, 0xC, 0xC, 0x3, 0x2, 0x1, 0x2, 0x3
];

const TEST_RECV_CNT_LOOKUP = bits[TEST_CNT_WIDTH][10]:[
    0x3, 0x2, 0x1, 0x3, 0x3, 0x3, 0x2, 0x1, 0x1, 0x1
];

// Structure to preserve state of the RLEEncTester for the next iteration
struct RLEEncTesterState {
    recv_cnt: u32,                    // number of received transactions
    total_cnt: u32,                   // total number of received symbols
    prev_symb: bits[TEST_SYMB_WIDTH], // previously received symbol
    prev_cnt: bits[TEST_CNT_WIDTH],   // previously received cnt
}

// Auxiliary proc for sending data to a RLE Encoder
proc RLEEncTestSender {
    data_s: chan<bits[TEST_SYMB_WIDTH]> out;

    init {(u32:0)}

    config (
        data_s: chan<bits[TEST_SYMB_WIDTH]> out,
    ) {(data_s,)}

    next (tok: token, cnt: u32) {
        let cnt_max = std::array_length(TEST_SEND_SYMB_LOOKUP);
        if (cnt < cnt_max) {
            let symb = TEST_SEND_SYMB_LOOKUP[cnt];
            let tok = send(tok, data_s, symb);
            let _ = trace_fmt!("Sent {} transactions, symbol: 0x{:x}", cnt, symb);
            cnt + u32:1
         } else {
            cnt
         }
    }
}

#[test_proc]
proc RLEEncTester {
    terminator: chan<bool> out;
    cnt_r: chan<bits[TEST_CNT_WIDTH]> in;
    symb_r: chan<bits[TEST_SYMB_WIDTH]> in;

    init {(
        RLEEncTesterState {
            recv_cnt: u32:0,
            total_cnt: u32:0,
            prev_symb: bits[TEST_SYMB_WIDTH]:0,
            prev_cnt: bits[TEST_CNT_WIDTH]:0,
        }
    )}

    config(terminator: chan<bool> out) {
        let (data_s, data_r) = chan<bits[TEST_SYMB_WIDTH]>;
        let (cnt_s, cnt_r) = chan<bits[TEST_CNT_WIDTH]>;
        let (symb_s, symb_r) = chan<bits[TEST_SYMB_WIDTH]>;

        spawn RLEEncTestSender(data_s);
        spawn RLEEnc<TEST_SYMB_WIDTH, TEST_CNT_WIDTH>(data_r, cnt_s, symb_s);
        (terminator, cnt_r, symb_r)
    }

    next(tok: token, state: RLEEncTesterState) {
        let (recv_cnt_tok, cnt) = recv(tok, cnt_r);
        let (recv_symb_tok, symb) = recv(tok, symb_r);
        let recv_tok = join(recv_cnt_tok, recv_symb_tok);

        let recv_cnt = state.recv_cnt + u32:1;
        let total_cnt = state.total_cnt + cnt as u32;
        let _ = trace_fmt!(
            "Received {} transactions, symbol: 0x{:x}, count: {}, total of {} symbols",
            recv_cnt, symb, cnt, total_cnt
        );

        // checks for expected values

        let exp_symb = TEST_RECV_SYMB_LOOKUP[state.recv_cnt];
        let exp_cnt = TEST_RECV_CNT_LOOKUP[state.recv_cnt];
        let _ = assert_eq(exp_symb, symb);
        let _ = assert_eq(exp_cnt, cnt);

        // if the symbol repeats, check if the previous cnt was max

        let symb_repeats = (state.recv_cnt != u32:0) && (state.prev_symb == symb);
        let max_cnt = std::unsigned_max_value<TEST_CNT_WIDTH>();
        let overflow = state.prev_cnt == max_cnt;
        let _ = if symb_repeats {
           let _ = assert_eq(overflow, true);
        } else {()};

        // check total count after the last expected receive

        let recv_symb_len = std::array_length(TEST_RECV_SYMB_LOOKUP);
        let recv_cnt_len = std::array_length(TEST_RECV_CNT_LOOKUP);
        let _ = assert_eq(recv_symb_len, recv_cnt_len);

        let exp_recv_cnt = recv_cnt_len;
        let exp_total_cnt = std::array_length(TEST_SEND_SYMB_LOOKUP) - u32:1;

        let _ = if (recv_cnt == exp_recv_cnt) {
            let _ = assert_eq(total_cnt, exp_total_cnt);
            let _ = send(recv_tok, terminator, true);
        } else {()};

        // state for the next iteration

        RLEEncTesterState {
            recv_cnt: recv_cnt,
            total_cnt: total_cnt,
            prev_symb: symb,
            prev_cnt: cnt,
        }
    }
}
