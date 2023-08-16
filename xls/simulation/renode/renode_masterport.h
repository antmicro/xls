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

#ifndef XLS_SIMULATION_RENODE_RENODE_MASTERPORT_H_
#define XLS_SIMULATION_RENODE_RENODE_MASTERPORT_H_

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "xls/simulation/generic/imasterport.h"

namespace xls::simulation::renode {

namespace generic = xls::simulation::generic;

class RenodeMasterPort : public generic::IMasterPort {
 public:
  RenodeMasterPort() = default;
  ~RenodeMasterPort() override = default;

  absl::Status RequestWrite(uint64_t address, uint64_t value,
                            AccessWidth type) override;
  absl::StatusOr<uint64_t> RequestRead(uint64_t address,
                                       AccessWidth type) override;
};

}  // namespace xls::simulation::renode

#endif  // XLS_SIMULATION_RENODE_RENODE_MASTERPORT_H_
