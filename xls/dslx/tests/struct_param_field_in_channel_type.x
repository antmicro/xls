#![feature(type_inference_v2)]

// A struct-valued parametric's field, used directly in a channel type,
// with no intermediate proc-body const needed (contrast with
// examples/ram_model_config.x, which hoists CONFIG.data_width into named
// consts first).

struct Cfg {
    width: u32,
}

struct NestedCfg {
    sub: Cfg,
}

pub proc Inner<CONFIG: Cfg> {
    c: chan<uN[CONFIG.width]> in;

    config(c: chan<uN[CONFIG.width]> in) { (c,) }
    init { () }
    next(state: ()) { () }
}

// Same idea, but the field is reached through a nested struct:
// CONFIG.sub.width rather than a single-level CONFIG.width.
pub proc InnerNested<CONFIG: NestedCfg> {
    c: chan<uN[CONFIG.sub.width]> in;

    config(c: chan<uN[CONFIG.sub.width]> in) { (c,) }
    init { () }
    next(state: ()) { () }
}

#[test_proc]
proc Outer {
    c: chan<u8> out;
    c_nested: chan<u16> out;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (s, r) = chan<u8>("c");
        let (s_nested, r_nested) = chan<u16>("c_nested");
        const CONFIG = Cfg { width: u32:8 };
        const NESTED_CONFIG = NestedCfg { sub: Cfg { width: u32:16 } };
        spawn Inner<CONFIG>(r);
        spawn InnerNested<NESTED_CONFIG>(r_nested);
        (s, s_nested, terminator)
    }

    init { () }

    next(state: ()) {
        let tok = send(join(), c, u8:1);
        let tok = send(tok, c_nested, u16:1);
        send(tok, terminator, true);
    }
}
