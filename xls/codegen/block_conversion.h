// Copyright 2021 The XLS Authors
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

#ifndef XLS_CODEGEN_BLOCK_CONVERSION_H_
#define XLS_CODEGEN_BLOCK_CONVERSION_H_

#include "absl/status/statusor.h"
#include "xls/codegen/codegen_options.h"
#include "xls/ir/block.h"
#include "xls/ir/function.h"
#include "xls/scheduling/pipeline_schedule.h"

namespace xls {
namespace verilog {

// Returns pipeline-stage prefixed signal name with the given string as the
// root. For example, for root `foo` the name might be: p3_foo. Nodes in the
// block generated by FunctionToPipelinedBlock and
// ProcToPipelinedBlock are named using this function.
std::string PipelineSignalName(absl::string_view root, int64_t stage);

// Converts a function in a pipelined (stateless) block. The pipeline is
// constructed using the given schedule. Registers are inserted between each
// stage.
absl::StatusOr<Block*> FunctionToPipelinedBlock(
    const PipelineSchedule& schedule, const CodegenOptions& options,
    Function* f);

// Converts a proc to a pipelined (stateless) block. The pipeline is
// constructed using the given schedule. Registers are inserted between each
// stage.
absl::StatusOr<Block*> ProcToPipelinedBlock(const PipelineSchedule& schedule,
                                            const CodegenOptions& options,
                                            Proc* proc);

// Converts a function into a combinational block. Function arguments become
// input ports, function return value becomes an output port. Returns a pointer
// to the block.
absl::StatusOr<Block*> FunctionToCombinationalBlock(
    Function* f, const CodegenOptions& options);

// TODO(meheff): 2022/05/25 Remove this overload.
absl::StatusOr<Block*> FunctionToCombinationalBlock(
    Function* f, absl::string_view block_name);

// Converts the given proc to a combinational block. Proc must be stateless
// (state type is an empty tuple). Streaming channels must have ready-valid flow
// control (FlowControl::kReadyValid). Receives/sends of these streaming
// channels become input/output ports with additional ready/valid ports for flow
// control. Receives/sends of single-value channels become input/output ports in
// the returned block.
absl::StatusOr<Block*> ProcToCombinationalBlock(Proc* proc,
                                                const CodegenOptions& options);

}  // namespace verilog
}  // namespace xls

#endif  // XLS_CODEGEN_BLOCK_CONVERSION_H_
