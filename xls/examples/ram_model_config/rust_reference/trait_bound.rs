// RamModel parametric over a type T: RamConfig -- default associated consts.
//
// Mirrors trait_style.x: each configuration is its own type implementing
// RamConfig, with associated consts providing defaults so an impl only needs
// to override what differs. Runs on stable Rust.
//
// Run with: rustc --edition 2021 trait_bound.rs -o /tmp/trait_bound && /tmp/trait_bound

trait RamConfig {
    const SIZE: u32;
    const WORD_PARTITION_SIZE: u32 = 0;
    const INITIALIZED: bool = false;
    const ASSERT_VALID_READ: bool = true;
}

struct DefaultRam;
impl RamConfig for DefaultRam {
    const SIZE: u32 = 256;
}

struct NoAssertRam;
impl RamConfig for NoAssertRam {
    const SIZE: u32 = 256;
    const ASSERT_VALID_READ: bool = false;
}

struct RamModel<T: RamConfig> {
    mem: Vec<Option<u32>>,
    _config: std::marker::PhantomData<T>,
}

impl<T: RamConfig> RamModel<T> {
    fn new() -> Self {
        let initial = if T::INITIALIZED { Some(0) } else { None };
        RamModel { mem: vec![initial; T::SIZE as usize], _config: std::marker::PhantomData }
    }

    fn write(&mut self, addr: usize, value: u32) {
        self.mem[addr] = Some(value);
    }

    fn read(&self, addr: usize) -> u32 {
        match self.mem[addr] {
            Some(v) => v,
            None if T::ASSERT_VALID_READ => panic!("read from uninitialized address {addr}"),
            None => 0,
        }
    }
}

fn main() {
    let mut ram = RamModel::<DefaultRam>::new();
    ram.write(0, 42);
    println!("DefaultRam[0] = {}", ram.read(0));

    let mut ram = RamModel::<NoAssertRam>::new();
    println!("NoAssertRam[5] (never written) = {}", ram.read(5));
    ram.write(5, 7);
    println!("NoAssertRam[5] (after write) = {}", ram.read(5));
}
