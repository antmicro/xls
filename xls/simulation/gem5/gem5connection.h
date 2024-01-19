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

#ifndef XLS_SIMULATION_GEM5_GEM5CONNECTION_H_
#define XLS_SIMULATION_GEM5_GEM5CONNECTION_H_

#include <cstdint>

#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/log_redirector.h"

namespace xls::simulation::gem5 {

struct Xls_C_ErrorOps {
  void* ctx;
  void(__attribute__((sysv_abi)) * reportError)(void*, uint8_t severity,
                                                const char* message);
};

class Gem5Connection final : public xls::simulation::generic::IConnection {
 public:
  Gem5Connection();
  ~Gem5Connection() override = default;
  static Gem5Connection& Instance();

  absl::Status Log(absl::LogSeverity level, std::string_view msg) override;

  absl::Status RequestReadMemToPeripheral(
      uint64_t address, size_t count, uint8_t* buf,
      OnRequestCompletionCB on_complete) override;
  absl::Status RequestWritePeripheralToMem(
      uint64_t address, size_t count, const uint8_t* buf,
      OnRequestCompletionCB on_complete) override;
  absl::Status SetInterrupt(uint64_t num, bool state) override;

 private:
  generic::LogRedirector log_redirector_;
};

}  // namespace xls::simulation::gem5

#endif  // XLS_SIMULATION_GEM5_GEM5CONNECTION_H_
