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

#include <filesystem>
#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "absl/log/check.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/match.h"
#include "absl/strings/str_format.h"
#include "absl/types/span.h"
#include "xls/codegen/vast/vast.h"
#include "xls/common/file/filesystem.h"
#include "xls/common/file/get_runfile_path.h"
#include "xls/common/file/temp_directory.h"
#include "xls/common/module_initializer.h"
#include "xls/common/status/status_macros.h"
#include "xls/common/subprocess.h"
#include "xls/simulation/verilog_include.h"
#include "xls/simulation/verilog_simulator.h"

namespace xls {
namespace verilog {
namespace {

static absl::Status SetUpIncludes(const std::filesystem::path& temp_dir,
                                  absl::Span<const VerilogInclude> includes) {
  for (const VerilogInclude& include : includes) {
    std::filesystem::path path = temp_dir / include.relative_path;
    XLS_RETURN_IF_ERROR(RecursivelyCreateDir(path.parent_path()));
    XLS_RETURN_IF_ERROR(SetFileContents(path, include.verilog_text));
  }
  return absl::OkStatus();
}

absl::StatusOr<std::pair<std::string, std::string>> InvokeVerilator(
    absl::Span<const std::string> args) {
  std::vector<std::string> args_vec;
  XLS_ASSIGN_OR_RETURN(std::filesystem::path verilator_path,
                       GetXlsRunfilePath("verilator/bin/verilator"));
  XLS_ASSIGN_OR_RETURN(std::filesystem::path verilated_header,
                       GetXlsRunfilePath("verilator/include/verilated.h"));
  std::filesystem::path verilator_root =
      verilated_header.parent_path().parent_path();
  args_vec.push_back(verilator_path.string());
  args_vec.insert(args_vec.end(), args.begin(), args.end());
  EnvironmentVariable verilator_root_env = {.name = "VERILATOR_ROOT",
                                            .value = verilator_root.string()};
  XLS_ASSIGN_OR_RETURN(SubprocessResult result,
                       InvokeSubprocess(args_vec, /*cwd=*/std::nullopt,
                                        /*optional_timeout=*/std::nullopt,
                                        {verilator_root_env}));
  if ((result.exit_status != 0 || !result.normal_termination) &&
      absl::StrContains(result.stderr_content, "not defined")) {
    return absl::InvalidArgumentError(
        absl::StrFormat("%s\nMacro undefined", result.stderr_content));
  }
  return SubprocessResultToStrings(SubprocessErrorAsStatus(std::move(result)));
}

absl::StatusOr<std::pair<std::string, std::string>> InvokeSimulation(
    const std::filesystem::path& binary, absl::Span<const std::string> args) {
  std::vector<std::string> args_vec = {binary.string()};
  args_vec.insert(args_vec.end(), args.begin(), args.end());
  XLS_ASSIGN_OR_RETURN(SubprocessResult result, InvokeSubprocess(args_vec));
  if (result.exit_status == 0 && result.normal_termination) {
    return std::make_pair(std::move(result.stdout_content),
                          std::move(result.stderr_content));
  }

  constexpr std::string_view kAssertionFailure = "Assertion failed";
  std::string diagnostic =
      absl::StrFormat("%s%s", result.stdout_content, result.stderr_content);
  if (absl::StrContains(diagnostic, kAssertionFailure)) {
    std::string_view diagnostic_text = diagnostic;
    size_t location_start = diagnostic_text.find("top.sv:");
    size_t location_end = location_start == std::string_view::npos
                              ? std::string_view::npos
                              : diagnostic_text.find(':', location_start + 7);
    size_t assertion_start = diagnostic_text.find(kAssertionFailure);
    size_t message_start = diagnostic_text.find(": ", assertion_start);
    size_t message_end = message_start == std::string_view::npos
                             ? std::string_view::npos
                             : diagnostic_text.find('\n', message_start + 2);
    if (location_start != std::string_view::npos &&
        location_end != std::string_view::npos &&
        message_start != std::string_view::npos) {
      std::string_view location =
          diagnostic_text.substr(location_start, location_end - location_start);
      std::string_view message = diagnostic_text.substr(
          message_start + 2, message_end - (message_start + 2));
      return absl::AbortedError(absl::StrFormat(
          "SystemVerilog assert failed at %s: %s", location, message));
    }
  }

  return SubprocessResultToStrings(SubprocessErrorAsStatus(std::move(result)));
}

void AppendMacroDefinitionsToArgs(
    absl::Span<const VerilogSimulator::MacroDefinition> macro_definitions,
    std::vector<std::string>& args) {
  args.push_back(
      absl::StrFormat("-D%s", VerilogSimulator::kSimulationMacroName));
  args.push_back(absl::StrFormat("-D%s", VerilogSimulator::kAssertOnMacroName));
  for (const VerilogSimulator::MacroDefinition& macro : macro_definitions) {
    if (macro.value.has_value()) {
      args.push_back(absl::StrFormat("-D%s=%s", macro.name, *macro.value));
    } else {
      args.push_back(absl::StrFormat("-D%s", macro.name));
    }
  }
}

class VerilatorSimulator : public VerilogSimulator {
 public:
  absl::StatusOr<std::pair<std::string, std::string>> Run(
      std::string_view text, FileType file_type,
      absl::Span<const MacroDefinition> macro_definitions,
      absl::Span<const VerilogInclude> includes) const override {
    XLS_ASSIGN_OR_RETURN(TempDirectory temp_top, TempDirectory::Create());
    XLS_RETURN_IF_ERROR(RecursivelyCreateDir(temp_top.path()));
    const std::filesystem::path& temp_dir = temp_top.path();

    std::string top_v_path = temp_dir / GetTopFileName(file_type);
    XLS_RETURN_IF_ERROR(SetFileContents(top_v_path, text));

    XLS_RETURN_IF_ERROR(SetUpIncludes(temp_dir, includes));
    std::filesystem::path build_dir = temp_dir / "obj_dir";
    std::filesystem::path simulation_binary = build_dir / "simulation";
    std::vector<std::string> args = {
        "--binary",
        "--timing",
        "--assert",
        "-Wno-fatal",
        top_v_path,
        "--Mdir",
        build_dir.string(),
        "-o",
        simulation_binary.filename().string(),
        absl::StrFormat("-I%s", temp_dir.string())};
    AppendMacroDefinitionsToArgs(macro_definitions, args);
    XLS_RETURN_IF_ERROR(InvokeVerilator(args).status());

    return InvokeSimulation(simulation_binary, {});
  }

  absl::Status RunSyntaxChecking(
      std::string_view text, FileType file_type,
      absl::Span<const MacroDefinition> macro_definitions,
      absl::Span<const VerilogInclude> includes) const override {
    XLS_ASSIGN_OR_RETURN(TempDirectory temp_top, TempDirectory::Create());
    XLS_RETURN_IF_ERROR(RecursivelyCreateDir(temp_top.path()));
    const std::filesystem::path& temp_dir = temp_top.path();

    std::string top_v_path = temp_dir / GetTopFileName(file_type);
    XLS_RETURN_IF_ERROR(SetFileContents(top_v_path, text));

    XLS_RETURN_IF_ERROR(SetUpIncludes(temp_dir, includes));

    std::vector<std::string> args = {
        "--lint-only", "--timing", "--assert",
        "-Wno-fatal",  top_v_path, absl::StrFormat("-I%s", temp_dir.string())};
    AppendMacroDefinitionsToArgs(macro_definitions, args);
    XLS_RETURN_IF_ERROR(InvokeVerilator(args).status());

    return absl::OkStatus();
  }

  bool DoesSupportSystemVerilog() const override { return true; }
  bool DoesSupportAssertions() const override { return true; }
};

XLS_REGISTER_MODULE_INITIALIZER(verilator_simulator, {
  CHECK_OK(GetVerilogSimulatorManagerSingleton().RegisterVerilogSimulator(
      "verilator", []() -> absl::StatusOr<std::unique_ptr<VerilogSimulator>> {
        return std::make_unique<VerilatorSimulator>();
      }));
});

}  // namespace
}  // namespace verilog
}  // namespace xls
