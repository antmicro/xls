// Copyright 2023 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

pub const DATA_WIDTH = u32:64;
pub const MAX_ID = u32::MAX;
pub const SYMBOL_WIDTH = u32:8;
pub const BLOCK_SIZE_WIDTH = u32:21;

pub type BlockData = bits[DATA_WIDTH];
pub type BlockPacketLength = u32;
pub type BlockSize = bits[BLOCK_SIZE_WIDTH];

pub enum BlockType : u2 {
    RAW = 0,
    RLE = 1,
    COMPRESSED = 2,
    RESERVED = 3,
}

pub struct BlockDataPacket {
    last: bool,
    last_block: bool,
    id: u32,
    data: BlockData,
    length: BlockPacketLength,
}
