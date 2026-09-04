// RamModel parametric over the config value.
//
// Mirrors old_style.x/impl_style.x: configuration is an ordinary struct
// value, and struct-update syntax (`..DEFAULT_RAM`) lets a caller override
// just the fields it cares about. Requires nightly Rust, since structs as
// const generic parameters (`adt_const_params`) are not yet stable.
//
// Run with: rustc +nightly --edition 2021 struct_update.rs -o /tmp/struct_update && /tmp/struct_update

#![feature(adt_const_params)]
use std::marker::ConstParamTy;

#[derive(PartialEq, Eq, ConstParamTy)]
struct RamConfig {
    size: u32,
    word_partition_size: u32,
    initialized: bool,
    assert_valid_read: bool,
}

const DEFAULT_RAM: RamConfig = RamConfig {
    size: 256,
    word_partition_size: 0,
    initialized: false,
    assert_valid_read: true,
};

const NO_ASSERT_RAM: RamConfig = RamConfig { assert_valid_read: false, ..DEFAULT_RAM };

struct RamModel<const CONFIG: RamConfig> {
    mem: Vec<Option<u32>>,
}

impl<const CONFIG: RamConfig> RamModel<CONFIG> {
    fn new() -> Self {
        let initial = if CONFIG.initialized { Some(0) } else { None };
        RamModel { mem: vec![initial; CONFIG.size as usize] }
    }

    fn write(&mut self, addr: usize, value: u32) {
        self.mem[addr] = Some(value);
    }

    fn read(&self, addr: usize) -> u32 {
        match self.mem[addr] {
            Some(v) => v,
            None if CONFIG.assert_valid_read => panic!("read from uninitialized address {addr}"),
            None => 0,
        }
    }
}

fn main() {
    let mut ram = RamModel::<DEFAULT_RAM>::new();
    ram.write(0, 42);
    println!("DEFAULT_RAM[0] = {}", ram.read(0));

    let mut ram = RamModel::<NO_ASSERT_RAM>::new();
    println!("NO_ASSERT_RAM[5] (never written) = {}", ram.read(5));
    ram.write(5, 7);
    println!("NO_ASSERT_RAM[5] (after write) = {}", ram.read(5));
}
