#![feature(type_inference_v2)]
#![feature(traits)]
#![feature(generics)]

// `T::CONST` used directly in a channel type inside a proc generic over an
// unconstrained `<T: type>`, with `T` substituted for a concrete struct
// implementing a trait. This is the minimal case of the pattern; see
// trait_bound_generic_ram_model.x for a realistic, larger-scale one.
trait RamConfig {
    const WIDTH: u32 = u32:32;
}

struct WideRam {}
impl RamConfig for WideRam {
    const WIDTH = u32:8;
}

pub proc Inner<T: type> {
    c: chan<uN[T::WIDTH]> in;

    config(c: chan<uN[T::WIDTH]> in) { (c,) }
    init { () }
    next(state: ()) { () }
}

#[test_proc]
proc Outer {
    c: chan<u8> out;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (s, r) = chan<u8>("c");
        spawn Inner<WideRam>(r);
        (s, terminator)
    }

    init { () }

    next(state: ()) {
        let tok = send(join(), c, u8:1);
        let tok = send(tok, terminator, true);
    }
}
