// Copyright 2023 The XLS Authors
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

#ifndef XLS_SIMULATION_GENERIC_RUNTIME_MANAGER_H_
#define XLS_SIMULATION_GENERIC_RUNTIME_MANAGER_H_

#include <memory>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "xls/interpreter/serial_proc_runtime.h"
#include "xls/ir/package.h"
#include "xls/simulation/generic/runtime_status.h"

namespace xls::simulation::generic {

class RuntimeManager final {
 public:
  // factory method
  static absl::StatusOr<std::unique_ptr<RuntimeManager>> Create(
      Package* package, bool use_jit);

  virtual ~RuntimeManager() = default;

  bool HasDeadlock() const;
  absl::Status Reset();

  // accessors to runtime and status
  SerialProcRuntime& Runtime();
  RuntimeStatus Status();

  absl::Status Update();

 private:
  explicit RuntimeManager(std::unique_ptr<SerialProcRuntime> runtime);

  std::unique_ptr<SerialProcRuntime> runtime_;
  bool deadlock_;
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_RUNTIME_MANAGER_H_
