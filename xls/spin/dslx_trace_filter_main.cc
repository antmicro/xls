// Copyright 2026 The XLS Authors
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

// Filters an EvaluatorResultsProto text proto trace (from interpreter_main
// --output_results_proto --trace_channels) down to channel events only,
// with values encoded as hex by default.
//
// Usage:
//   dslx_trace_filter --input=trace.textproto [--output=out.json]
//   [--format=hex]

#include <cstdint>
#include <iostream>
#include <string>
#include <string_view>

#include "absl/flags/flag.h"
#include "absl/log/log.h"
#include "absl/status/status.h"
#include "absl/strings/escaping.h"
#include "absl/strings/str_format.h"
#include "google/protobuf/text_format.h"
#include "xls/common/exit_status.h"
#include "xls/common/file/filesystem.h"
#include "xls/common/init_xls.h"
#include "xls/common/status/status_macros.h"
#include "xls/ir/evaluator_result.pb.h"

ABSL_FLAG(std::string, input, "",
          "Input EvaluatorResultsProto text proto file.");
ABSL_FLAG(std::string, output, "-",
          "Output file path, or '-' for stdout (default).");
ABSL_FLAG(std::string, format, "hex",
          "Value encoding: 'hex' (default), 'decimal', 'binary', or 'base64'.");

namespace xls::spin {
namespace {

// Encode the little-endian bytes of a BitsProto as a 0x-prefixed big-endian
// hex string padded to the full byte width.
std::string BitsToHex(const std::string& data) {
  std::string result = "0x";
  for (size_t i = data.size(); i-- > 0;) {
    // char is signed; cast to uint8_t to prevent sign extension.
    uint8_t byte_val = static_cast<uint8_t>(data[i]);
    absl::StrAppendFormat(&result, "%02x", byte_val);
  }
  return result;
}

// Encode little-endian bytes as a 0b-prefixed binary string, MSB first,
// trimmed to bit_count significant bits.
std::string BitsToBinary(const std::string& data, int64_t bit_count) {
  std::string result = "0b";
  for (int64_t i = bit_count - 1; i >= 0; --i) {
    int64_t byte_idx = i / 8;
    int64_t bit_idx = i % 8;
    int64_t data_size = static_cast<int64_t>(data.size());
    char byte = (byte_idx < data_size) ? data[byte_idx] : 0;
    result += ((byte >> bit_idx) & 1) ? '1' : '0';
  }
  return result;
}

// Decode little-endian bytes to an unsigned 64-bit integer.
uint64_t BitsToUint(const std::string& data) {
  uint64_t value = 0;
  for (size_t i = data.size(); i-- > 0;) {
    // char is signed; cast to uint8_t to prevent sign extension into value.
    uint8_t byte_val = static_cast<uint8_t>(data[i]);
    value = (value << 8) | byte_val;
  }
  return value;
}

// Format a ValueProto as a JSON object: {"bit_count": N, "data": <encoded>}.
std::string FormatValue(const ValueProto& vp, std::string_view fmt) {
  if (!vp.has_bits()) {
    return "{\"bit_count\": 0, \"data\": \"(non-bits)\"}";
  }
  const std::string& data = vp.bits().data();
  int64_t bit_count = vp.bits().bit_count();
  std::string encoded;
  if (fmt == "decimal") {
    encoded = absl::StrFormat("%u", BitsToUint(data));
  } else if (fmt == "binary") {
    encoded = absl::StrFormat("\"%s\"", BitsToBinary(data, bit_count));
  } else if (fmt == "base64") {
    encoded = absl::StrFormat("\"%s\"", absl::Base64Escape(data));
  } else {
    encoded = absl::StrFormat("\"%s\"", BitsToHex(data));
  }
  return absl::StrFormat("{\"bit_count\": %d, \"data\": %s}", bit_count,
                         encoded);
}

std::string DirectionString(TraceChannelProto::Direction dir) {
  switch (dir) {
    case TraceChannelProto::SEND:
      return "SEND";
    case TraceChannelProto::RECV:
      return "RECV";
    default:
      return "UNKNOWN";
  }
}

std::string FormatTrace(const EvaluatorResultsProto& proto,
                        std::string_view fmt) {
  std::string json = "[\n";
  bool first = true;
  for (const EvaluatorResultProto& result : proto.results()) {
    for (const TraceMessageProto& msg : result.events().trace_msgs()) {
      if (!msg.has_channel()) continue;
      const TraceChannelProto& ch = msg.channel();
      if (!first) json += ",\n";
      first = false;
      absl::StrAppendFormat(
          &json,
          "  {\"channel_name\": \"%s\", \"direction\": \"%s\", \"value\": %s}",
          ch.channel_name(), DirectionString(ch.direction()),
          FormatValue(ch.value(), fmt));
    }
  }
  json += "\n]\n";
  return json;
}

absl::Status Run() {
  std::string input_path = absl::GetFlag(FLAGS_input);
  if (input_path.empty()) {
    return absl::InvalidArgumentError("--input is required.");
  }
  std::string fmt = absl::GetFlag(FLAGS_format);
  if (fmt != "hex" && fmt != "decimal" && fmt != "binary" && fmt != "base64") {
    return absl::InvalidArgumentError(
        "--format must be 'hex', 'decimal', 'binary', or 'base64'.");
  }

  std::string content;
  XLS_ASSIGN_OR_RETURN(content, GetFileContents(input_path));

  EvaluatorResultsProto proto;
  if (!google::protobuf::TextFormat::ParseFromString(content, &proto)) {
    return absl::InvalidArgumentError("Failed to parse input text proto.");
  }

  std::string json = FormatTrace(proto, fmt);

  std::string output_path = absl::GetFlag(FLAGS_output);
  if (output_path == "-") {
    std::cout << json;
  } else {
    XLS_RETURN_IF_ERROR(SetFileContents(output_path, json));
  }
  return absl::OkStatus();
}

}  // namespace
}  // namespace xls::spin

int main(int argc, char** argv) {
  xls::InitXls(argv[0], argc, argv);
  return xls::ExitStatus(xls::spin::Run());
}
