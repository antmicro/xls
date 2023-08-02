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

#ifndef XLS_SIMULATION_GENERIC_IIRQ_STUB_H_
#define XLS_SIMULATION_GENERIC_IIRQ_STUB_H_

#include <functional>

#include "absl/status/status.h"
#include "xls/simulation/generic/iirq.h"

namespace xls::simulation::generic {

class IIRQStub : public IIRQ {
 public:
  IIRQStub();
  virtual ~IIRQStub() = default;

  bool GetIRQ() override;
  absl::Status UpdateIRQ() override;

  void SetPolicy(std::function<bool(void)> policy);

 private:
  bool status_;
  std::function<bool(void)> policy_;
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_IIRQ_STUB_H_
