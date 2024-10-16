const FOO: u32[1] = [ u32:0 ];

#[test_proc]
proc ExampleProc {
    init {}
    config(_: chan<bool> out) {}

    next (_: ()) {
        for (i, ()): (u32, ()) in range(u32:0, u32:1) {
            let foobar = FOO[i];
            for (_, ()): (u32, ()) in range(u32:0, foobar) {}(());
        }(());
    }
}

