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

// Shared trace-comparison utilities for SPIN <-> DSLX channel-event comparison.
//
// Used by both the promela_trace_compare CLI binary and the
// promela_generator_test to normalise channel names, parse per-tool JSON trace
// formats, and compare per-channel event sequences.

#ifndef XLS_SPIN_TRACE_COMPARE_H_
#define XLS_SPIN_TRACE_COMPARE_H_

#include <cstdint>
#include <map>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/status/status.h"

namespace xls {
class Package;
}  // namespace xls

namespace xls::spin {

// Map from (normalised_channel_name, direction) to the ordered sequence of
// integer values exchanged on that channel.
using TraceMap =
    std::map<std::pair<std::string, std::string>, std::vector<int64_t>>;

// Maps DSLX hierarchy paths to local variable name -> Promela channel name.
// Outer key: full DSLX proc hierarchy path including instance numbers,
//   e.g. "MultiplyBy4Test->MultiplyBy4#0->MultiplyBy2#0".
// Inner key: local channel variable name without leading _, e.g. "req_r".
// Value: canonical Promela channel name without leading _, e.g. "req".
using ChanNameMap =
    absl::flat_hash_map<std::string,
                        absl::flat_hash_map<std::string, std::string>>;

// Builds a ChanNameMap by walking the proc instantiation tree in `package`.
// Channel names are resolved transitively so inner procs map to the actual
// owned channel names rather than to their parent's interface alias names.
ChanNameMap BuildChanNameMap(const xls::Package& package);

// Strips the leading underscore that SPIN adds to channel names.
// e.g. "_req" -> "req", "req" -> "req".
std::string NormalizeSpinChannel(std::string_view name);

// Maps a DSLX fully-qualified channel name to the canonical Promela channel
// name using `map` (built from the IR via BuildChanNameMap).  Falls back to
// stripping the _r / _s direction suffix when the path is not in the map
// (covers events emitted by the root/test proc, which is never a child).
// e.g. "PassthroughTest->Passthrough#0::req_r" -> "req" (via IR map)
//      "PassthroughTest::req_s" -> "req" (fallback: strip _s)
std::string NormalizeDslxChannel(std::string_view name,
                                 const ChanNameMap& map = {});

// Parses the newline-delimited JSON written by `spin -Q` into *out*.
// Each recognised line has the form:
//   {"channel_name":"X","direction":"Y","value":N}
// SPIN's 32-bit signed values are reinterpreted as uint32 to match the
// raw-bits encoding that DSLX produces.
// If terminator_channel is non-empty, parsing stops after the first SEND event
// on that channel; events after the terminator are discarded.
absl::Status ParseSpinTrace(std::string_view json, TraceMap& out,
                            std::string_view terminator_channel = "");

// Parses an EvaluatorResultsProto text proto produced by
// `interpreter_main --output_results_proto --trace_channels` into *out*.
// Use a map from BuildChanNameMap to resolve channel names via IR ground truth.
// If terminator_channel is non-empty, parsing stops after the first SEND event
// on that channel; events after the terminator are discarded.
absl::Status ParseDslxTrace(std::string_view textproto, TraceMap& out,
                            const ChanNameMap& map = {},
                            std::string_view terminator_channel = "");

// Compares two TraceMaps channel by channel.
// Returns OK if every channel present in both maps carries identical value
// sequences.  Channels present in only one map are skipped (not a failure).
// On mismatch the returned status message lists the differing channels.
absl::Status CompareTraces(const TraceMap& spin, const TraceMap& dslx);

}  // namespace xls::spin

#endif  // XLS_SPIN_TRACE_COMPARE_H_
