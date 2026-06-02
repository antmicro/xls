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

// Compares a SPIN simulation trace against a DSLX interpreter trace.
//
// Channel event order is compared per-channel: within a single channel the
// sequence of values (and direction) must be identical in both traces.
// Different channels may interleave differently between DSLX and SPIN.
//
// Usage:
//   promela_trace_compare --spin_trace=<spin.json> --dslx_trace=<dslx.json>

#include <iostream>
#include <string>

#include "absl/flags/flag.h"
#include "absl/status/status.h"
#include "xls/common/file/filesystem.h"
#include "xls/common/init_xls.h"
#include "xls/common/status/status_macros.h"
#include "xls/spin/trace_compare.h"

ABSL_FLAG(std::string, spin_trace, "", "Path to SPIN simulation trace JSON.");
ABSL_FLAG(std::string, dslx_trace, "", "Path to DSLX interpreter trace JSON.");

namespace xls::spin {
namespace {

absl::Status Run() {
  std::string spin_path = absl::GetFlag(FLAGS_spin_trace);
  std::string dslx_path = absl::GetFlag(FLAGS_dslx_trace);
  if (spin_path.empty() || dslx_path.empty()) {
    return absl::InvalidArgumentError(
        "--spin_trace and --dslx_trace are required.");
  }

  std::string spin_json, dslx_json;
  XLS_ASSIGN_OR_RETURN(spin_json, GetFileContents(spin_path));
  XLS_ASSIGN_OR_RETURN(dslx_json, GetFileContents(dslx_path));

  TraceMap spin_events, dslx_events;
  XLS_RETURN_IF_ERROR(ParseSpinTrace(spin_json, spin_events));
  XLS_RETURN_IF_ERROR(ParseDslxTrace(dslx_json, dslx_events));
  return CompareTraces(spin_events, dslx_events);
}

}  // namespace
}  // namespace xls::spin

int main(int argc, char** argv) {
  xls::InitXls(argv[0], argc, argv);
  absl::Status status = xls::spin::Run();
  if (!status.ok()) {
    std::cerr << status.message() << "\n";
    return 1;
  }
  return 0;
}
