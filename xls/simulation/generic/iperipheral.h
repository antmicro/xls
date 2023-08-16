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

#ifndef XLS_SIMULATION_GENERIC_IPERIPHERAL_H_
#define XLS_SIMULATION_GENERIC_IPERIPHERAL_H_

#include "absl/status/status.h"
#include "absl/status/statusor.h"

namespace xls::simulation::generic {

// IPeripheral is used in conjunction with IConnection,
// and implements callbacks for:
// - read/write operations,
// - reset,
// - IRQ and
// - simulation tick.
// Calls:
//  - CheckRequest() checks if address is mapped to channel manager
//  - HandleRead() reads data from address `addr`
//  - HandleWrite() writes data starting ad address `addr`
//  - HandleIRQ() checks if any IRQ is ready
//  - HandleTick() advances simulation
//  - Reset() is used to reset a peripheral.
class IPeripheral {
 public:
  virtual absl::Status CheckRequest(uint64_t addr, AccessWidth width) = 0;
  virtual absl::StatusOr<uint64_t> HandleRead(uint64_t addr,
                                              AccessWidth width) = 0;
  virtual absl::Status HandleWrite(uint64_t addr, AccessWidth width,
                                   uint64_t payload) = 0;
  virtual absl::StatusOr<IRQEnum> HandleIRQ() = 0;
  virtual absl::Status HandleTick() = 0;

  virtual absl::Status Reset() = 0;
  virtual ~IPeripheral() = default;
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_IPERIPHERAL_H_
