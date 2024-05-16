// Copyright 2020 The XLS Authors
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
//

#include <fstream>
#include <memory>

#include "gtest/gtest.h"
#include "xls/common/file/filesystem.h"
#include "xls/common/file/get_runfile_path.h"
#include "xls/common/status/matchers.h"
#include "xls/interpreter/interpreter_proc_runtime.h"
#include "xls/interpreter/serial_proc_runtime.h"
#include "xls/jit/jit_proc_runtime.h"
#include "xls/ir/events.h"
#include "xls/ir/ir_parser.h"
#include "xls/modules/zstd/data_generator.h"
#include "zstd.h"

namespace xls {
namespace {

class ZstdDecodedPacket {
 public:
  static std::optional<ZstdDecodedPacket> MakeZstdDecodedPacket(Value packet) {
    // Expect tuple
    if (!packet.IsTuple()) return std::nullopt;
    // Expect exactly 3 fields
    if (packet.size() != 3) return std::nullopt;
    for (int i = 0; i < 3; i++) {
      // Expect fields to be Bits
      if (!packet.element(i).IsBits()) return std::nullopt;
      // All fields must fit in 64bits
      if (!packet.element(i).bits().FitsInUint64()) return std::nullopt;
    }

    std::vector<uint8_t> data = packet.element(0).bits().ToBytes();
    absl::StatusOr<uint64_t> len = packet.element(1).bits().ToUint64();
    if (!len.ok()) return std::nullopt;
    uint64_t length = *len;
    bool last = packet.element(2).bits().IsOne();

    return ZstdDecodedPacket(data, length, last);
  }

  std::vector<uint8_t> GetData() { return data; }

  uint64_t GetLength() { return length; }

  bool IsLast() { return last; }

  const std::string PrintData() const {
    std::stringstream s;
    for (int j = 0; j < sizeof(uint64_t) && j < data.size(); j++) {
      s << "0x" << std::setw(2) << std::setfill('0') << std::right << std::hex
        << (unsigned int)data[j] << std::dec << ", ";
    }
    return s.str();
  }

  friend std::ostream& operator<<(std::ostream& os,
                                  const ZstdDecodedPacket& packet) {
    return os << "ZstdDecodedPacket { data: {" << packet.PrintData()
              << "}, length: " << packet.length << " last: " << packet.last
              << "}" << std::endl;
  }

 private:
  ZstdDecodedPacket(std::vector<uint8_t> data, uint64_t length, bool last)
      : data(data), length(length), last(last) {}

  std::vector<uint8_t> data;
  uint64_t length;
  bool last;
};

class ZstdDecoderTest : public ::testing::Test {
 public:
  void SetUp() {
    XLS_ASSERT_OK_AND_ASSIGN(std::filesystem::path ir_path,
                             xls::GetXlsRunfilePath(this->ir_file));
    XLS_ASSERT_OK_AND_ASSIGN(std::string ir_text,
                             xls::GetFileContents(ir_path));
    XLS_ASSERT_OK_AND_ASSIGN(this->package, xls::Parser::ParsePackage(ir_text));
    XLS_ASSERT_OK_AND_ASSIGN(
        this->interpreter,
        CreateJitSerialProcRuntime(this->package.get()));

    auto& queue_manager = this->interpreter->queue_manager();
    XLS_ASSERT_OK_AND_ASSIGN(this->recv_queue, queue_manager.GetQueueByName(
                                                   this->recv_channel_name));
    XLS_ASSERT_OK_AND_ASSIGN(this->send_queue, queue_manager.GetQueueByName(
                                                   this->send_channel_name));
  }

  void PrintTraceMessages(std::string pname) {
    XLS_ASSERT_OK_AND_ASSIGN(Proc * proc, this->package->GetProc(pname));
    const InterpreterEvents& events =
        this->interpreter->GetInterpreterEvents(proc);

    if (!events.trace_msgs.empty()) {
      for (const auto& tm : events.trace_msgs) {
        std::cout << "[TRACE] " << tm.message << std::endl;
      }
    }
  }

  const char* proc_name = "__zstd_dec__ZstdDecoderTest_0_next";
  const char* recv_channel_name = "zstd_dec__output_s";
  const char* send_channel_name = "zstd_dec__input_r";

  const char* ir_file = "xls/modules/zstd/zstd_dec_test.ir";

  std::unique_ptr<Package> package;
  std::unique_ptr<SerialProcRuntime> interpreter;
  ChannelQueue *recv_queue, *send_queue;

  void PrintVector(absl::Span<uint8_t> vec) {
    for (int i = 0; i < vec.size(); i += 8) {
      std::cout << "0x" << std::hex << std::setw(3) << std::left << i
                << std::dec << ": ";
      for (int j = 0; j < sizeof(uint64_t) && (i + j) < vec.size(); j++) {
        std::cout << std::setfill('0') << std::setw(2) << std::hex << (unsigned int)vec[i + j]
                  << std::dec << " ";
      }
      std::cout << std::endl;
    }
  }

  std::vector<uint8_t> DecompressWithLibZSTD(std::vector<uint8_t> encoded_frame) {
      std::vector<uint8_t> decoded_frame;

      size_t buff_out_size = ZSTD_DStreamOutSize();
      void* const buff_out = new uint8_t[buff_out_size];

      ZSTD_DCtx* const dctx = ZSTD_createDCtx();
      EXPECT_FALSE(dctx == NULL);

      void* const frame = static_cast<void*>(encoded_frame.data());
      size_t const frame_size = encoded_frame.size();
      // Put the whole frame in the buffer
      ZSTD_inBuffer input_buffer = {frame, frame_size, 0};

      while (input_buffer.pos < input_buffer.size) {
        ZSTD_outBuffer output_buffer = {buff_out, buff_out_size, 0};
        size_t decomp_result = ZSTD_decompressStream(dctx, &output_buffer, &input_buffer);
        EXPECT_FALSE(ZSTD_isError(decomp_result));

        // Append output buffer contents to output vector
        decoded_frame.insert(decoded_frame.end(), (uint8_t*)output_buffer.dst, ((uint8_t*)output_buffer.dst + output_buffer.pos));

        if (decomp_result == 0) {
          EXPECT_TRUE(decomp_result == 0 && output_buffer.pos < output_buffer.size);
          break;
        }
      }

      ZSTD_freeDCtx(dctx);
      delete[] buff_out;

      return decoded_frame;
  }

  void ParseAndCompareWithZstd(std::vector<uint8_t> frame) {
    std::vector<uint8_t> lib_decomp = DecompressWithLibZSTD(frame);
    size_t lib_decomp_size = lib_decomp.size();
    std::cout << "lib_decomp_size: " << lib_decomp_size << std::endl;

    std::vector<uint8_t> sim_decomp;
    size_t sim_decomp_size_words =
        (lib_decomp_size + sizeof(uint64_t) - 1) / sizeof(uint64_t);
    size_t sim_decomp_size_bytes =
        (lib_decomp_size + sizeof(uint64_t) - 1) * sizeof(uint64_t);
    sim_decomp.reserve(sim_decomp_size_bytes);

    // Send compressed frame to decoder simulation
    for (int i = 0; i < frame.size(); i += 8) {
      auto span = absl::MakeSpan(frame.data() + i, 8);
      auto value = Value(Bits::FromBytes(span, 64));
      XLS_EXPECT_OK(this->send_queue->Write(value));
      XLS_EXPECT_OK(this->interpreter->Tick());
    }

    // Tick decoder simulation until we get expected amount of output data
    // batches on output channel queue
    std::optional<int64_t> ticks_timeout = std::nullopt;
    absl::flat_hash_map<Channel*, int64_t> output_counts = {
        {this->recv_queue->channel(), sim_decomp_size_words}};
    XLS_EXPECT_OK(
        this->interpreter->TickUntilOutput(output_counts, ticks_timeout));

    // Read decompressed data from output channel queue
    for (int i = 0; i < sim_decomp_size_words; i++) {
      auto read_value = this->recv_queue->Read();
      EXPECT_EQ(read_value.has_value(), true);
      auto packet =
          ZstdDecodedPacket::MakeZstdDecodedPacket(read_value.value());
      EXPECT_EQ(packet.has_value(), true);
      auto word_vec = packet->GetData();
      auto valid_length = packet->GetLength() / CHAR_BIT;
      std::copy(begin(word_vec), begin(word_vec) + valid_length,
                back_inserter(sim_decomp));
    }

    PrintTraceMessages("__zstd_dec__ZstdDecoderTest_0_next");
    PrintTraceMessages("__zstd_dec__ZstdDecoderTest__ZstdDecoder_0_next");
    PrintTraceMessages("__xls_modules_zstd_dec_demux__ZstdDecoderTest__ZstdDecoder__BlockDecoder__DecoderDemux_0_next");
    PrintTraceMessages("__xls_modules_zstd_raw_block_dec__ZstdDecoderTest__ZstdDecoder__BlockDecoder__RawBlockDecoder_0_next");
    PrintTraceMessages("__xls_modules_zstd_rle_block_dec__ZstdDecoderTest__ZstdDecoder__BlockDecoder__RleBlockDecoder__RleDataPacker_0_next");
    PrintTraceMessages("__xls_modules_rle_rle_dec__ZstdDecoderTest__ZstdDecoder__BlockDecoder__RleBlockDecoder__RunLengthDecoder_0__21_8_next");
    PrintTraceMessages("__xls_modules_zstd_rle_block_dec__ZstdDecoderTest__ZstdDecoder__BlockDecoder__RleBlockDecoder__BatchPacker_0_next");
    PrintTraceMessages("__xls_modules_zstd_rle_block_dec__ZstdDecoderTest__ZstdDecoder__BlockDecoder__RleBlockDecoder_0_next");
    PrintTraceMessages("__xls_modules_zstd_raw_block_dec__ZstdDecoderTest__ZstdDecoder__BlockDecoder__RawBlockDecoder_1_next");
    PrintTraceMessages("__xls_modules_zstd_dec_mux__ZstdDecoderTest__ZstdDecoder__BlockDecoder__DecoderMux_0_next");
    PrintTraceMessages("__xls_modules_zstd_block_dec__ZstdDecoderTest__ZstdDecoder__BlockDecoder_0_next");
    PrintTraceMessages("__xls_modules_zstd_sequence_executor__ZstdDecoderTest__ZstdDecoder__SequenceExecutor__RamWrRespHandler_0__13_next");
    PrintTraceMessages("__xls_modules_zstd_sequence_executor__ZstdDecoderTest__ZstdDecoder__SequenceExecutor__RamRdRespHandler_0_next");
    PrintTraceMessages("__xls_modules_zstd_sequence_executor__ZstdDecoderTest__ZstdDecoder__SequenceExecutor_0__64_0_0_0_13_8192_65536_next");
    PrintTraceMessages("__xls_modules_zstd_repacketizer__ZstdDecoderTest__ZstdDecoder__Repacketizer_0_next");

    EXPECT_EQ(lib_decomp_size, sim_decomp.size());
    for (int i = 0; i < lib_decomp_size; i++) {
      EXPECT_EQ(lib_decomp[i], sim_decomp[i]);
    }
  }
};

/* TESTS */

TEST(ZstdLib, Version) { ASSERT_EQ(ZSTD_VERSION_STRING, "1.4.7"); }

TEST_F(ZstdDecoderTest, ParseFrameWithEmptyRawBlocks) {
  int seed = 3;  // Arbitrary seed value for small ZSTD frame
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RAW);
  PrintVector(absl::MakeSpan(frame->data(), frame->size()));
  EXPECT_TRUE(frame.ok());
  this->ParseAndCompareWithZstd(frame.value());
}

TEST_F(ZstdDecoderTest, ParseFrameWithEmptyRawBlocks1) {
  int seed = 12;  // Arbitrary seed value for small ZSTD frame
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RAW);
  PrintVector(absl::MakeSpan(frame->data(), frame->size()));
  EXPECT_TRUE(frame.ok());
  this->ParseAndCompareWithZstd(frame.value());
}

TEST_F(ZstdDecoderTest, ParseFrameWithEmptyRawBlocks2) {
  int seed = 15;  // Arbitrary seed value for small ZSTD frame
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RAW);
  PrintVector(absl::MakeSpan(frame->data(), frame->size()));
  EXPECT_TRUE(frame.ok());
  this->ParseAndCompareWithZstd(frame.value());
}

TEST_F(ZstdDecoderTest, ParseFrameWithEmptyRawBlocks3) {
  int seed = 17;  // Arbitrary seed value for small ZSTD frame
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RAW);
  PrintVector(absl::MakeSpan(frame->data(), frame->size()));
  EXPECT_TRUE(frame.ok());
  this->ParseAndCompareWithZstd(frame.value());
}

TEST_F(ZstdDecoderTest, ParseFrameWithEmptyRawBlocks4) {
  int seed = 32;  // Arbitrary seed value for small ZSTD frame
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RAW);
  PrintVector(absl::MakeSpan(frame->data(), frame->size()));
  EXPECT_TRUE(frame.ok());
  this->ParseAndCompareWithZstd(frame.value());
}

TEST_F(ZstdDecoderTest, ParseFrameWithRleBlocks) {
  int seed = 6;  // Arbitrary seed value for small ZSTD frame
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RLE);
  EXPECT_TRUE(frame.ok());
  PrintVector(absl::MakeSpan(frame->data(), frame->size()));
  this->ParseAndCompareWithZstd(frame.value());
}

class ZstdDecoderSeededTest : public ZstdDecoderTest,
                              public ::testing::WithParamInterface<uint32_t> {
 public:
  static const uint32_t random_frames_count = 50;
};

// Test `random_frames_count` instances of randomly generated valid
// frames, generated with `decodecorpus` tool.

TEST_P(ZstdDecoderSeededTest, ParseMultipleFramesWithRawBlocks) {
  auto seed = GetParam();
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RAW);
  EXPECT_TRUE(frame.ok());
  this->ParseAndCompareWithZstd(frame.value());
}

TEST_P(ZstdDecoderSeededTest, ParseMultipleFramesWithRleBlocks) {
  auto seed = GetParam();
  auto frame = zstd::GenerateFrame(seed, zstd::BlockType::RLE);
  EXPECT_TRUE(frame.ok());
  this->ParseAndCompareWithZstd(frame.value());
}

INSTANTIATE_TEST_SUITE_P(
    ZstdDecoderSeededTest, ZstdDecoderSeededTest,
    ::testing::Range<uint32_t>(0, ZstdDecoderSeededTest::random_frames_count));

}  // namespace
}  // namespace xls
