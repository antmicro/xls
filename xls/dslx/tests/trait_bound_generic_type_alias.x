#![feature(type_inference_v2)]
#![feature(traits)]
#![feature(generics)]

// `T::CONST` referenced through a proc-scope `type` alias, both directly and
// via an intermediate derived const, inside a proc generic over an
// unconstrained `<T: type>`. Aliasing a parametric struct type this way
// (e.g. `type Foo = SomeStruct<T::CONST>`) is a separate, still-unresolved
// gap -- see trait_bound_generic_ram_model.x's proc body, which inlines its
// channel types for exactly that reason.
trait RamConfig {
    const WIDTH: u32 = u32:32;
}

struct WideRam {}
impl RamConfig for WideRam {
    const WIDTH = u32:8;
}

pub proc Direct<T: type> {
    type MyType = uN[T::WIDTH];
    c: chan<MyType> in;

    config(c: chan<MyType> in) { (c,) }
    init { () }
    next(state: ()) { () }
}

pub proc Derived<T: type> {
    const DOUBLE_WIDTH = T::WIDTH * u32:2;
    type MyType = uN[DOUBLE_WIDTH];
    c: chan<MyType> in;

    config(c: chan<MyType> in) { (c,) }
    init { () }
    next(state: ()) { () }
}

#[test_proc]
proc Outer {
    direct_c: chan<u8> out;
    derived_c: chan<u16> out;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (direct_s, direct_r) = chan<u8>("direct_c");
        let (derived_s, derived_r) = chan<u16>("derived_c");
        spawn Direct<WideRam>(direct_r);
        spawn Derived<WideRam>(derived_r);
        (direct_s, derived_s, terminator)
    }

    init { () }

    next(state: ()) {
        let tok = send(join(), direct_c, u8:1);
        let tok = send(tok, derived_c, u16:1);
        let tok = send(tok, terminator, true);
    }
}
