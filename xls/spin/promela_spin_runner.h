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

// Entry points for Promela generation + SPIN simulation + trace comparison.
// RunPromelaTraceVerification is IR-level; RunSpinVerification is DSLX-level.

#ifndef XLS_SPIN_PROMELA_SPIN_RUNNER_H_
#define XLS_SPIN_PROMELA_SPIN_RUNNER_H_

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "xls/ir/evaluator_result.pb.h"
#include "xls/ir/package.h"
#include "xls/spin/promela_generator.h"

namespace xls::spin {

// Locates the spin executable: tries Bazel runfiles first, then PATH.
absl::StatusOr<std::filesystem::path> FindSpinBinary();

// IR-level: generates Promela, runs `spin -c -Q`, compares its trace against
// `dslx_results_proto`. Give each repeated call its own `artifact_subdir`.
absl::Status RunPromelaTraceVerification(
    Package* package, std::string_view dslx_results_proto,
    const std::filesystem::path& spin_binary,
    const PromelaGeneratorOptions& options = {},
    std::string_view artifact_subdir = "spin_verify");

// Options forwarded from interpreter_main to RunSpinVerification.
struct SpinVerificationOptions {
  std::string dslx_stdlib_path;
  std::vector<std::filesystem::path> dslx_paths;
  std::optional<std::string> test_filter;
  bool type_inference_v2 = false;
  // See RunPromelaTraceVerification's artifact_subdir.
  std::string artifact_subdir = "spin_verify";
};

// DSLX-level: full pipeline from source text -- picks a #[test_proc] (using
// options.test_filter if there are several), converts it, and verifies it.
absl::Status RunSpinVerification(
    std::string_view dslx_source, std::string_view entry_module_path,
    std::string_view module_name,
    const xls::EvaluatorResultsProto& results_proto,
    const SpinVerificationOptions& options = {});

}  // namespace xls::spin

#endif  // XLS_SPIN_PROMELA_SPIN_RUNNER_H_
