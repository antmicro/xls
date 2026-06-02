proc Counter {
  config() { () }
  init { u32:0 }
  next(state: u32) { state + u32:1 }
}
