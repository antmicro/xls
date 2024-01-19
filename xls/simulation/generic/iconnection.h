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

#ifndef XLS_SIMULATION_GENERIC_ICONNECTION_H_
#define XLS_SIMULATION_GENERIC_ICONNECTION_H_

#include <string_view>

#include "absl/log/log.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"

namespace xls::simulation::generic {

// IConnection is used in conjunction with IPeripheral and provides methods to
// communicate with a system simulator from XLS runtime.
class IConnection {
 public:
  // A C-compatible structure for a callback to be executed when a memory
  // transfer.is completed.
  // Use C-style callback to avoid allocating data with std::function.
  // Instead we assume a the context's lifetime exceeds the request completion
  // frame.
  struct OnRequestCompletionCB {
    // An argument to be passed to `complete()`
    void* ctx;
    // Called with `ctx` on completion of a memory transfer
    // This might get caled from outside the XLS code.
    void(__attribute__((sysv_abi)) * complete)(void* ctx);
  };

  // WARNING: It's ILLEGAL to move the passed object until the callback gets
  // executed. Always consider the object's scope when using this function.
  template <typename T>
  static inline OnRequestCompletionCB make_callback(T& functor) {
    return OnRequestCompletionCB{.ctx = &functor, .complete = [](void* ctx) {
                                   (*static_cast<T*>(ctx))();
                                 }};
  }

  // Print a message in simulator's console.
  virtual absl::Status Log(absl::LogSeverity level, std::string_view msg) = 0;

  // Request a memory transfer from the simulated system's bus address space
  // to a user-provided buffer `buf`. The `on_complete` callback is called
  // either by XLS runtime or the simulator once the transfer is completed.
  // All transfers are expected to succeed eventually.
  virtual absl::Status RequestReadMemToPeripheral(
      uint64_t address, size_t count, uint8_t* buf,
      OnRequestCompletionCB on_complete) = 0;
  // Request a memory transfer from a user provided buffer `buf` to the
  // simulated system's bus address space. The `on_complete` callback is called
  // either by XLS runtime or the simulator once the transfer is completed.
  // All transfers are expected to succeed eventually.
  virtual absl::Status RequestWritePeripheralToMem(
      uint64_t address, size_t count, const uint8_t* buf,
      OnRequestCompletionCB on_complete) = 0;
  // Set the state of an interrupt `num` to `state`.
  // (true => high, false => low)
  virtual absl::Status SetInterrupt(uint64_t num, bool state) = 0;

  virtual ~IConnection() = default;
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_ICONNECTION_H_
