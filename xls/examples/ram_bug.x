import xls.examples.ram

const ADDR_WIDTH = u32:3;
const DATA_WIDTH = u32:8;
const NUM_PARTITIONS = u32:0;

type Data = bits[DATA_WIDTH];

proc SingleProcRamExample {
    input_r: chan<Data> in;
    output_s: chan<Data> out;
    req_s: chan<ram::RWRamReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> out;
    resp_r: chan<ram::RWRamResp<DATA_WIDTH>> in;
    wr_comp_r: chan<()> in;

    config(
        input_r: chan<Data> in,
        output_s: chan<Data> out,
        req_s: chan<ram::RWRamReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> out,
        resp_r: chan<ram::RWRamResp<DATA_WIDTH>> in,
        wr_comp_r: chan<()> in
    ) {
        (input_r, output_s, req_s, resp_r, wr_comp_r)
    }

    init {  }

    next(tok0: token, state: ()) {
        let (tok1, data) = recv(tok0, input_r);
        let tok2_0 = send(tok1, req_s, ram::RWRamReq {
            data, addr: u3:0,
            write_mask: (),
            read_mask: (),
            we: true,
            re: false
        });
        let tok2_1 = send(tok1, output_s, data);
        let tok2 = join(tok2_0, tok2_1);
        let (tok3, _) = recv(tok2, wr_comp_r);

        let (tok, _) = recv_if(tok0, resp_r, false, ram::RWRamResp { data: u8:0 });
    }
}

proc RamWriter {
    input_r: chan<u8> in;
    req_s: chan<ram::RWRamReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> out;

    config(
        input_r: chan<u8> in,
        req_s: chan<ram::RWRamReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> out
    ) {
        (input_r, req_s)
    }

    init {  }

    next(tok: token, state: ()) {
        let (tok, data) = recv(tok, input_r);
        let tok0_1 = send(tok, req_s, ram::RWRamReq {
            data, addr: u3:0,
            write_mask: (),
            read_mask: (),
            we: true,
            re: false
        });
    }
}

proc NestedProcRamExample {
    input_r: chan<Data> in;
    output_s: chan<Data> out;
    ram_input_s: chan<Data> out;
    req_s: chan<ram::RWRamReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> out;
    resp_r: chan<ram::RWRamResp<DATA_WIDTH>> in;
    wr_comp_r: chan<()> in;

    config(
        input_r: chan<Data> in,
        output_s: chan<Data> out,
        req_s: chan<ram::RWRamReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> out,
        resp_r: chan<ram::RWRamResp<DATA_WIDTH>> in,
        wr_comp_r: chan<()> in
    ) {
        let (ram_input_s, ram_input_r) = chan<Data>;
        spawn RamWriter(ram_input_r, req_s);
        (input_r, output_s, ram_input_s, req_s, resp_r, wr_comp_r)
    }

    init {  }

    next(tok0: token, state: ()) {
        let (tok1, data) = recv(tok0, input_r);
        let tok2_0 = send(tok1, ram_input_s, data);
        let tok2_1 = send(tok1, output_s, data);
        let tok2 = join(tok2_0, tok2_1);
        let (tok3, _) = recv(tok2, wr_comp_r);

        let (tok, _) = recv_if(tok0, resp_r, false, ram::RWRamResp { data: u8:0 });
    }
}
