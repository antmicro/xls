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

#include "xls/spin/trace_compare.h"

#include <string_view>

#include "gmock/gmock.h"
#include "gtest/gtest.h"

namespace xls {
namespace spin {
namespace {

using ::testing::ElementsAre;

testing::AssertionResult CompareMaps(const TraceMap& spin,
                                     const TraceMap& dslx) {
  auto s = CompareTraces(spin, dslx);
  if (!s.ok()) return testing::AssertionFailure() << s.message();
  return testing::AssertionSuccess();
}

TEST(TraceCompareTest, NormalizeSpinChannel) {
  // SPIN channel names have a leading underscore that must be stripped.
  EXPECT_EQ(NormalizeSpinChannel("_req"), "req");
  EXPECT_EQ(NormalizeSpinChannel("req"), "req");
  EXPECT_EQ(NormalizeSpinChannel("_terminator"), "terminator");
}

TEST(TraceCompareTest, NormalizeDslxChannel) {
  // DSLX channel names carry a proc-path prefix (after '::') and a _r/_s
  // direction suffix, both of which must be stripped.
  EXPECT_EQ(NormalizeDslxChannel("PassthroughTest->Sub::req_r"), "req");
  EXPECT_EQ(NormalizeDslxChannel("req_s"), "req");
  EXPECT_EQ(NormalizeDslxChannel("req"), "req");
  EXPECT_EQ(NormalizeDslxChannel("result_r"), "result");
}

TEST(TraceCompareTest, ParseSpinTrace_Basic) {
  // Parses the newline-delimited JSON written by spin -Q; channel names are
  // normalised (leading _ stripped) and values stored in order.
  constexpr std::string_view kJson =
      "{\"channel_name\":\"_req\",\"direction\":\"SEND\",\"value\":1}\n"
      "{\"channel_name\":\"_resp\",\"direction\":\"RECV\",\"value\":42}\n"
      "{\"channel_name\":\"_req\",\"direction\":\"SEND\",\"value\":2}\n";
  TraceMap out;
  EXPECT_TRUE(ParseSpinTrace(kJson, out).ok());
  EXPECT_THAT((out[{"req", "SEND"}]), ElementsAre(1, 2));
  EXPECT_THAT((out[{"resp", "RECV"}]), ElementsAre(42));
}

TEST(TraceCompareTest, ParseSpinTrace_NegativeValueReinterpret) {
  // SPIN's 32-bit signed -1 must be reinterpreted as uint32 (4294967295) so
  // it matches the raw-bits encoding DSLX produces.
  constexpr std::string_view kJson =
      "{\"channel_name\":\"_ch\",\"direction\":\"SEND\",\"value\":-1}\n";
  TraceMap out;
  EXPECT_TRUE(ParseSpinTrace(kJson, out).ok());
  EXPECT_THAT((out[{"ch", "SEND"}]), ElementsAre(4294967295LL));
}

TEST(TraceCompareTest, CompareMaps_Match) {
  // Identical per-channel value sequences must produce AssertionSuccess.
  TraceMap spin, dslx;
  spin[{"req", "SEND"}] = {1, 2, 3};
  dslx[{"req", "SEND"}] = {1, 2, 3};
  EXPECT_TRUE(CompareMaps(spin, dslx));
}

TEST(TraceCompareTest, CompareMaps_Mismatch) {
  // Any differing value in a shared channel must produce AssertionFailure.
  TraceMap spin, dslx;
  spin[{"req", "SEND"}] = {1, 2, 3};
  dslx[{"req", "SEND"}] = {1, 2, 99};
  EXPECT_FALSE(CompareMaps(spin, dslx));
}

TEST(TraceCompareTest, CompareMaps_AsymmetricKeys) {
  // A channel present in only one trace is skipped -- not a failure.
  TraceMap spin, dslx;
  spin[{"req", "SEND"}] = {1};
  dslx[{"resp", "RECV"}] = {1};
  EXPECT_TRUE(CompareMaps(spin, dslx));
}

}  // namespace
}  // namespace spin
}  // namespace xls
