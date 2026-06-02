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

#include "xls/spin/promela_spin_runner.h"

#include <filesystem>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "gmock/gmock.h"
#include "google/protobuf/text_format.h"
#include "gtest/gtest.h"
#include "xls/common/file/filesystem.h"
#include "xls/common/file/get_runfile_path.h"
#include "xls/common/file/temp_directory.h"
#include "xls/common/status/matchers.h"
#include "xls/common/subprocess.h"
#include "xls/ir/evaluator_result.pb.h"
#include "xls/ir/ir_test_base.h"
#include "xls/spin/promela_generator.h"

namespace xls {
namespace spin {
namespace {

using ::absl_testing::IsOk;
using ::absl_testing::StatusIs;
using ::testing::HasSubstr;
using ::testing::Not;

// Runs interpreter_main --trace_channels on src_path and returns the parsed
// EvaluatorResultsProto. Strips TESTBRIDGE_TEST_ONLY so the interpreter is
// not constrained to the current test's filter.
absl::StatusOr<EvaluatorResultsProto> RunInterpreter(
    const std::filesystem::path& src_path,
    const std::filesystem::path& dslx_path_dir) {
  XLS_ASSIGN_OR_RETURN(auto tmp, TempDirectory::Create("interp_proto"));
  XLS_ASSIGN_OR_RETURN(auto interp,
                       GetXlsRunfilePath("xls/dslx/interpreter_main"));
  const std::filesystem::path proto_path = tmp.path() / "trace.pb.txt";
  std::vector<std::string> argv = {
      "/usr/bin/env",
      "-u",
      "TESTBRIDGE_TEST_ONLY",
      "-u",
      "XML_OUTPUT_FILE",
      interp.string(),
      src_path.string(),
      "--dslx_path=" + dslx_path_dir.string(),
      "--trace_channels",
      "--output_results_proto=" + proto_path.string(),
  };
  XLS_ASSIGN_OR_RETURN(SubprocessResult r, InvokeSubprocess(argv));
  if (r.exit_status != 0) {
    return absl::InternalError("interpreter_main failed:\n" + r.stderr_content);
  }
  XLS_ASSIGN_OR_RETURN(std::string text, GetFileContents(proto_path));
  EvaluatorResultsProto proto;
  if (!google::protobuf::TextFormat::ParseFromString(text, &proto)) {
    return absl::InvalidArgumentError("proto parse failed");
  }
  return proto;
}

class PromelaSpinRunnerTest : public IrTestBase {
 protected:
  // Reads a Bazel runfile as IR text and parses it into a Package.
  absl::StatusOr<std::unique_ptr<Package>> LoadIrFile(
      std::string_view runfile_path) {
    XLS_ASSIGN_OR_RETURN(auto path, GetXlsRunfilePath(runfile_path));
    XLS_ASSIGN_OR_RETURN(std::string text, GetFileContents(path));
    return ParsePackageNoVerify(text);
  }
};

// =============================================================================
// FindSpinBinary
// =============================================================================

TEST_F(PromelaSpinRunnerTest, FindSpinBinary_ReturnsPath) {
  EXPECT_THAT(FindSpinBinary(), IsOk());
}

// =============================================================================
// RunPromelaTraceVerification
// =============================================================================

TEST_F(PromelaSpinRunnerTest, RunPromelaTraceVerification_NonexistentBinary) {
  XLS_ASSERT_OK_AND_ASSIGN(auto pkg,
                           LoadIrFile("xls/spin/testdata/passthrough.ir"));
  PromelaGeneratorOptions opts;
  opts.emit_termination_hook = true;
  EXPECT_THAT(
      RunPromelaTraceVerification(pkg.get(), /*dslx_results_proto=*/"",
                                  std::filesystem::path("no_such_spin_binary"),
                                  opts),
      Not(IsOk()));
}

TEST_F(PromelaSpinRunnerTest, RunPromelaTraceVerification_MatchingTrace) {
  XLS_ASSERT_OK_AND_ASSIGN(auto pkg,
                           LoadIrFile("xls/spin/testdata/passthrough.ir"));
  XLS_ASSERT_OK_AND_ASSIGN(
      auto src, GetXlsRunfilePath("xls/spin/testdata/passthrough.x"));
  XLS_ASSERT_OK_AND_ASSIGN(auto proto, RunInterpreter(src, src.parent_path()));
  std::string proto_text;
  ASSERT_TRUE(google::protobuf::TextFormat::PrintToString(proto, &proto_text));
  XLS_ASSERT_OK_AND_ASSIGN(auto spin_bin, FindSpinBinary());
  PromelaGeneratorOptions opts;
  opts.emit_termination_hook = true;
  EXPECT_THAT(
      RunPromelaTraceVerification(pkg.get(), proto_text, spin_bin, opts),
      IsOk());
}

TEST_F(PromelaSpinRunnerTest, RunPromelaTraceVerification_MismatchedTrace) {
  XLS_ASSERT_OK_AND_ASSIGN(auto pkg,
                           LoadIrFile("xls/spin/testdata/passthrough.ir"));
  // PassthroughTest sends req values 10..1; this proto claims a single SEND
  // of value 1 on req_s, which differs from the 10-element SPIN trace.
  constexpr std::string_view kWrongProto = R"pb(
results {
  events {
    trace_msgs {
      channel {
        channel_name: "req_s"
        direction: SEND
        value { bits { data: "\001" } }
      }
    }
  }
}
)pb";
  XLS_ASSERT_OK_AND_ASSIGN(auto spin_bin, FindSpinBinary());
  PromelaGeneratorOptions opts;
  opts.emit_termination_hook = true;
  EXPECT_THAT(
      RunPromelaTraceVerification(pkg.get(), kWrongProto, spin_bin, opts),
      StatusIs(absl::StatusCode::kFailedPrecondition));
}

// Minimal IR: state starts at 0, assertion (state != 0) fires immediately.
// The Assert node has label "state_nonzero" and source span fake.x:5:5.
constexpr std::string_view kAssertFailIr = R"(
package assert_fail

file_number 0 "fake.x"

top proc __test__P_0_next<>(__state: bits[32], init={0}) {
  __token: token = after_all(id=1)
  literal.2: bits[32] = literal(value=0, id=2)
  ne.3: bits[1] = ne(__state, literal.2, id=3)
  assert.4: token = assert(__token, ne.3, message="Assertion failure via assert! @ fake.x:5:5-5:30", label="state_nonzero", id=4)
  next (__state: __state)
}
)";

// DSLX assert_msg at the same source location as the Assert node above.
constexpr std::string_view kSameAssertProto = R"pb(
results {
  events {
    assert_msgs {
      message: "FailureError: fake.x:5:5-5:30 The program being interpreted failed! state_nonzero"
    }
  }
}
)pb";

// DSLX assert_msg at a different source location.
constexpr std::string_view kDifferentAssertProto = R"pb(
results {
  events {
    assert_msgs {
      message: "FailureError: other.x:99:1-99:20 The program being interpreted failed! other"
    }
  }
}
)pb";

TEST_F(PromelaSpinRunnerTest,
       RunPromelaTraceVerification_AssertionSameAsInterpreter) {
  XLS_ASSERT_OK_AND_ASSIGN(auto pkg, ParsePackageNoVerify(kAssertFailIr));
  XLS_ASSERT_OK_AND_ASSIGN(auto spin_bin, FindSpinBinary());
  PromelaGeneratorOptions opts;
  // SPIN fires the same assertion as the DSLX interpreter: model is consistent.
  EXPECT_THAT(
      RunPromelaTraceVerification(pkg.get(), kSameAssertProto, spin_bin, opts),
      IsOk());
}

TEST_F(PromelaSpinRunnerTest,
       RunPromelaTraceVerification_AssertionDifferentFromInterpreter) {
  XLS_ASSERT_OK_AND_ASSIGN(auto pkg, ParsePackageNoVerify(kAssertFailIr));
  XLS_ASSERT_OK_AND_ASSIGN(auto spin_bin, FindSpinBinary());
  PromelaGeneratorOptions opts;
  // SPIN fires assertion "state_nonzero" but DSLX failed at a different site.
  EXPECT_THAT(
      RunPromelaTraceVerification(pkg.get(), kDifferentAssertProto, spin_bin,
                                  opts),
      StatusIs(absl::StatusCode::kFailedPrecondition,
               HasSubstr("state_nonzero")));
}

TEST_F(PromelaSpinRunnerTest,
       RunPromelaTraceVerification_AssertionNotInInterpreter) {
  XLS_ASSERT_OK_AND_ASSIGN(auto pkg, ParsePackageNoVerify(kAssertFailIr));
  XLS_ASSERT_OK_AND_ASSIGN(auto spin_bin, FindSpinBinary());
  PromelaGeneratorOptions opts;
  // SPIN fires assertion "state_nonzero" but DSLX had no assertion failures.
  EXPECT_THAT(
      RunPromelaTraceVerification(pkg.get(), /*dslx_results_proto=*/"",
                                  spin_bin, opts),
      StatusIs(absl::StatusCode::kFailedPrecondition,
               HasSubstr("state_nonzero")));
}

TEST_F(PromelaSpinRunnerTest, RunPromelaTraceVerification_Deadlock) {
  XLS_ASSERT_OK_AND_ASSIGN(auto pkg,
                           LoadIrFile("xls/spin/testdata/deadlock.ir"));
  XLS_ASSERT_OK_AND_ASSIGN(auto spin_bin, FindSpinBinary());
  PromelaGeneratorOptions opts;
  opts.emit_termination_hook = true;
  EXPECT_THAT(
      RunPromelaTraceVerification(pkg.get(), /*dslx_results_proto=*/"",
                                  spin_bin, opts),
      StatusIs(absl::StatusCode::kDeadlineExceeded));
}

// =============================================================================
// RunSpinVerification
// =============================================================================

TEST_F(PromelaSpinRunnerTest, RunSpinVerification_NoTestProc) {
  // A module with no #[test_proc] returns OK immediately without running SPIN.
  constexpr std::string_view kDslx = R"(
proc SimpleProc {
    config() {}
    init { () }
    next(state: ()) {}
}
)";
  EvaluatorResultsProto empty_proto;
  EXPECT_THAT(RunSpinVerification(kDslx, "simple.x", "simple", empty_proto),
              IsOk());
}

TEST_F(PromelaSpinRunnerTest, RunSpinVerification_Passthrough) {
  XLS_ASSERT_OK_AND_ASSIGN(
      auto src, GetXlsRunfilePath("xls/spin/testdata/passthrough.x"));
  XLS_ASSERT_OK_AND_ASSIGN(std::string dslx_source, GetFileContents(src));
  XLS_ASSERT_OK_AND_ASSIGN(auto proto, RunInterpreter(src, src.parent_path()));
  SpinVerificationOptions opts;
  opts.type_inference_v2 = true;
  EXPECT_THAT(
      RunSpinVerification(dslx_source, src.string(), "passthrough", proto,
                          opts),
      IsOk());
}

// Two trivial test_procs that each send immediately on terminator.
// No user channels so an empty EvaluatorResultsProto is a valid (empty) trace.
constexpr std::string_view kTwoTestProcsDslx =
    "#![feature(type_inference_v2)]\n"
    "\n"
    "#[test_proc]\n"
    "proc FirstTest {\n"
    "    terminator: chan<bool> out;\n"
    "    config(terminator: chan<bool> out) { (terminator,) }\n"
    "    init { () }\n"
    "    next(state: ()) {\n"
    "        let tok = send(join(), terminator, true);\n"
    "    }\n"
    "}\n"
    "\n"
    "#[test_proc]\n"
    "proc SecondTest {\n"
    "    terminator: chan<bool> out;\n"
    "    config(terminator: chan<bool> out) { (terminator,) }\n"
    "    init { () }\n"
    "    next(state: ()) {\n"
    "        let tok = send(join(), terminator, true);\n"
    "    }\n"
    "}\n";

TEST_F(PromelaSpinRunnerTest, RunSpinVerification_MultipleProcs_WithFilter) {
  XLS_ASSERT_OK_AND_ASSIGN(auto tmp, TempDirectory::Create("two_procs"));
  const std::filesystem::path src = tmp.path() / "test.x";
  XLS_ASSERT_OK(SetFileContents(src, kTwoTestProcsDslx));
  EvaluatorResultsProto empty_proto;
  SpinVerificationOptions opts;
  opts.type_inference_v2 = true;
  opts.test_filter = "SecondTest";
  EXPECT_THAT(
      RunSpinVerification(kTwoTestProcsDslx, src.string(), "test", empty_proto,
                          opts),
      IsOk());
}

TEST_F(PromelaSpinRunnerTest, RunSpinVerification_MultipleProcs_WithoutFilter) {
  XLS_ASSERT_OK_AND_ASSIGN(auto tmp, TempDirectory::Create("two_procs"));
  const std::filesystem::path src = tmp.path() / "test.x";
  XLS_ASSERT_OK(SetFileContents(src, kTwoTestProcsDslx));
  EvaluatorResultsProto empty_proto;
  SpinVerificationOptions opts;
  opts.type_inference_v2 = true;
  // No test_filter: runner picks FirstTest with a LOG(WARNING).
  EXPECT_THAT(
      RunSpinVerification(kTwoTestProcsDslx, src.string(), "test", empty_proto,
                          opts),
      IsOk());
}

}  // namespace
}  // namespace spin
}  // namespace xls
