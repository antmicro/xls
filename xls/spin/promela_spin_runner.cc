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

#include <cstdlib>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "absl/log/log.h"
#include "absl/status/status.h"
#include "absl/strings/str_format.h"
#include "google/protobuf/text_format.h"
#include "re2/re2.h"
#include "xls/common/file/filesystem.h"
#include "xls/common/file/get_runfile_path.h"
#include "xls/common/file/temp_directory.h"
#include "xls/common/status/status_macros.h"
#include "xls/common/subprocess.h"
#include "xls/dslx/create_import_data.h"
#include "xls/dslx/frontend/proc.h"
#include "xls/dslx/ir_convert/ir_converter.h"
#include "xls/dslx/parse_and_typecheck.h"
#include "xls/dslx/virtualizable_file_system.h"
#include "xls/dslx/warning_kind.h"
#include "xls/ir/evaluator_result.pb.h"
#include "xls/ir/function_base.h"
#include "xls/ir/nodes.h"
#include "xls/ir/package.h"
#include "xls/passes/optimization_pass_pipeline.h"
#include "xls/spin/promela_generator.h"
#include "xls/spin/trace_compare.h"

namespace xls::spin {

absl::StatusOr<std::filesystem::path> FindSpinBinary() {
  auto runfile = GetXlsRunfilePath("spin", "spin");
  if (runfile.ok() && std::filesystem::exists(*runfile)) return *runfile;
  // Fall back to PATH lookup: posix_spawnp searches PATH for relative names.
  return std::filesystem::path("spin");
}

absl::Status RunPromelaTraceVerification(
    Package* package, std::string_view dslx_results_proto,
    const std::filesystem::path& spin_binary,
    const PromelaGeneratorOptions& options,
    std::string_view artifact_subdir) {
  XLS_ASSIGN_OR_RETURN(std::string pml, PromelaGenerator::Generate(package, options));

  // Write artifacts into the Bazel test-output dir if set, else a temp dir
  // deleted on return (getenv, not the testonly GetUndeclaredOutputDirectory).
  std::optional<TempDirectory> owned_tmp;
  std::filesystem::path dir;
  if (const char* undeclared = std::getenv("TEST_UNDECLARED_OUTPUTS_DIR");
      undeclared != nullptr && *undeclared != '\0') {
    dir = std::filesystem::path(undeclared) / artifact_subdir;
    XLS_RETURN_IF_ERROR(RecursivelyCreateDir(dir));
  } else {
    XLS_ASSIGN_OR_RETURN(owned_tmp, TempDirectory::Create("promela_verify"));
    dir = owned_tmp->path();
  }

  const std::filesystem::path pml_path = dir / "model.pml";
  const std::filesystem::path spin_trace_path = dir / "spin_trace.json";
  const std::filesystem::path spin_log_path = dir / "spin_output.log";
  const std::filesystem::path dslx_trace_path = dir / "dslx_trace.textproto";
  XLS_RETURN_IF_ERROR(SetFileContents(pml_path, pml));
  // Dump the DSLX-side trace alongside the SPIN trace so a mismatch can be
  // diffed by hand instead of only seeing spin_trace.json on disk.
  XLS_RETURN_IF_ERROR(SetFileContents(dslx_trace_path, dslx_results_proto));

  std::vector<std::string> argv = {
      spin_binary.string(), "-c", "-Q", spin_trace_path.string(),
      pml_path.string(),
  };
  XLS_ASSIGN_OR_RETURN(SubprocessResult spin_result,
                       InvokeSubprocess(argv, dir));
  // SPIN reports all errors (assertion violations, crashes) on stdout; stderr
  // is typically empty even on failure.
  const std::string& spin_out = spin_result.stdout_content;
  XLS_RETURN_IF_ERROR(SetFileContents(spin_log_path, spin_out));
  if (spin_result.exit_status != 0) {
    if (spin_out.find("assertion violated") != std::string::npos) {
      // Identify which assertion SPIN fired via the XLS_ASSERT:<label> printf
      // we embed before every assert() in the generated Promela.
      std::string spin_label;
      RE2::PartialMatch(spin_out, R"(XLS_ASSERT:([^\n]+))", &spin_label);

      // Find the Assert node with that label and extract its source line:col
      // from the node's message field ("... @ path/file.x:L:C-L:C").
      std::string assert_loc;  // "LINE:COL"
      for (FunctionBase* fb : package->GetFunctionBases()) {
        for (Node* node : fb->nodes()) {
          if (!node->Is<Assert>()) continue;
          const Assert* a = node->As<Assert>();
          if (a->label().has_value() && *a->label() == spin_label) {
            RE2::PartialMatch(a->message(), R"(:(\d+:\d+))", &assert_loc);
            break;
          }
        }
        if (!assert_loc.empty()) break;
      }

      // Parse DSLX assert_msgs and check whether any hit the same source line
      // ("FailureError: path/file.x:LINE:COL-LINE:COL The program...").
      xls::EvaluatorResultsProto dslx_proto;
      bool dslx_had_assertion = false;
      bool dslx_same_assertion = false;
      if (google::protobuf::TextFormat::ParseFromString(
              std::string(dslx_results_proto), &dslx_proto)) {
        for (const auto& r : dslx_proto.results()) {
          for (const auto& am : r.events().assert_msgs()) {
            dslx_had_assertion = true;
            if (!assert_loc.empty()) {
              std::string dslx_loc;
              RE2::PartialMatch(am.message(), R"(:(\d+:\d+))", &dslx_loc);
              if (dslx_loc == assert_loc) dslx_same_assertion = true;
            }
          }
        }
      }

      if (dslx_same_assertion) {
        // Both DSLX and SPIN hit the same assertion: the Promela model is
        // consistent.  Return OK; the caller fails on the DSLX side.
        return absl::OkStatus();
      }
      if (dslx_had_assertion) {
        return absl::FailedPreconditionError(absl::StrFormat(
            "Promela assertion \"%s\" violated but does not match the "
            "assertion fired by the DSLX interpreter.",
            spin_label));
      }
      return absl::FailedPreconditionError(absl::StrFormat(
          "Promela assertion \"%s\" violated but the DSLX interpreter "
          "reported no assertion failures.",
          spin_label));
    }
    return absl::InternalError(absl::StrFormat(
        "spin failed (exit %d):\n%s", spin_result.exit_status, spin_out));
  }
  // In simulation mode SPIN exits 0 on deadlock but prints "timeout" on
  // stdout and writes an empty trace file.
  if (spin_out.find("timeout") != std::string::npos) {
    return absl::DeadlineExceededError(absl::StrFormat(
        "SPIN simulation reached a deadlock (\"timeout\").\n"
        "The Promela model blocked with no enabled transitions.\n"
        "SPIN output:\n%s",
        spin_out));
  }

  XLS_ASSIGN_OR_RETURN(std::string spin_json, GetFileContents(spin_trace_path));
  ChanNameMap chan_map = BuildChanNameMap(*package);
  std::string_view term_chan =
      options.emit_termination_hook ? "terminator" : "";
  TraceMap spin_events, dslx_events;
  XLS_RETURN_IF_ERROR(ParseSpinTrace(spin_json, spin_events, term_chan));
  XLS_RETURN_IF_ERROR(
      ParseDslxTrace(dslx_results_proto, dslx_events, chan_map, term_chan));
  return CompareTraces(spin_events, dslx_events);
}

absl::Status RunSpinVerification(
    std::string_view dslx_source, std::string_view entry_module_path,
    std::string_view module_name,
    const xls::EvaluatorResultsProto& results_proto,
    const SpinVerificationOptions& options) {
  // Parse the module to discover #[test_proc] entries.
  dslx::ImportData import_data(dslx::CreateImportData(
      options.dslx_stdlib_path, options.dslx_paths, dslx::kAllWarningsSet,
      std::make_unique<dslx::RealFilesystem>()));
  XLS_ASSIGN_OR_RETURN(dslx::TypecheckedModule tm,
                       dslx::ParseAndTypecheck(dslx_source, entry_module_path,
                                               module_name, &import_data));

  std::vector<dslx::TestProc*> test_procs = tm.module->GetTestProcs();
  if (test_procs.empty()) {
    LOG(WARNING) << "--spin_verify: no #[test_proc] found in "
                 << entry_module_path << "; skipping SPIN verification";
    return absl::OkStatus();
  }

  // Pick one test proc to verify.
  std::string spin_top;
  if (test_procs.size() == 1) {
    spin_top = test_procs[0]->identifier();
  } else {
    if (options.test_filter.has_value()) {
      RE2 re(*options.test_filter);
      for (dslx::TestProc* tp : test_procs) {
        if (RE2::FullMatch(tp->identifier(), re) && spin_top.empty()) {
          spin_top = tp->identifier();
        }
      }
    }
    if (spin_top.empty()) {
      spin_top = test_procs[0]->identifier();
      LOG(WARNING) << "--spin_verify: multiple #[test_proc] entries; using "
                   << spin_top;
    }
  }

  // Convert the selected test proc to optimised IR.
  bool printed_error = true;
  dslx::ConvertOptions ir_conv_opts = {
      .emit_positions = true,
      .emit_assert = true,
      .verify_ir = true,
      .warnings_as_errors = false,
      .warnings = dslx::kAllWarningsSet,
      .convert_tests = true,
      .type_inference_v2 = options.type_inference_v2,
      .lower_to_proc_scoped_channels = true,
  };
  std::array<std::string_view, 1> module_path{entry_module_path};
  XLS_ASSIGN_OR_RETURN(
      dslx::PackageConversionData conv,
      dslx::ConvertFilesToPackage(module_path, options.dslx_stdlib_path,
                                  options.dslx_paths, ir_conv_opts, spin_top,
                                  module_name, &printed_error));
  XLS_RETURN_IF_ERROR(RunOptimizationPassPipeline(conv.package.get()).status());

  // Serialise the DSLX trace proto to text format expected by ParseDslxTrace.
  std::string proto_text;
  if (!google::protobuf::TextFormat::PrintToString(results_proto,
                                                   &proto_text)) {
    return absl::InternalError("Failed to serialize EvaluatorResultsProto");
  }

  XLS_ASSIGN_OR_RETURN(std::filesystem::path spin_bin, FindSpinBinary());
  PromelaGeneratorOptions pml_opts;
  pml_opts.emit_termination_hook = true;
  pml_opts.emit_source_hints = true;
  pml_opts.emit_progress_labels = true;
  return RunPromelaTraceVerification(conv.package.get(), proto_text, spin_bin,
                                     pml_opts, options.artifact_subdir);
}

}  // namespace xls::spin
