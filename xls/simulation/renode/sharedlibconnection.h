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

#ifndef XLS_SIMULATION_RENODE_SHAREDLIBCONNECTION_H_
#define XLS_SIMULATION_RENODE_SHAREDLIBCONNECTION_H_

#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "absl/log/log.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/iperipheral.h"
#include "xls/simulation/generic/log_redirector.h"
#include "xls/simulation/renode/renode_protocol.h"
#include "xls/simulation/renode/renode_protocol_native.h"

namespace xls::simulation::renode {
namespace generic = xls::simulation::generic;

// Singleton class, not instantiable directly by the user
class SharedLibConnection final : public generic::IConnection {
 public:
  // Singleton getter
  static SharedLibConnection& Instance();
  static void SetLogRedirection(bool on);

  absl::Status Log(absl::LogSeverity level, std::string_view msg) override;

  absl::Status RequestReadMemToPeripheral(
      uint64_t address, size_t count, uint8_t* buf,
      OnRequestCompletionCB on_complete) override;
  absl::Status RequestWritePeripheralToMem(
      uint64_t address, size_t count, const uint8_t* buf,
      OnRequestCompletionCB on_complete) override;
  absl::Status SetInterrupt(uint64_t num, bool state) override;

 protected:
  // NOTE: for more information on Renode native VerilatedPeripheral interface
  // see xls/simulation/renode/renode_protocol_native.h

  // C++ interface to functions exported by Renode. C++ code calls these and
  // they in turn call Renode-provided callbacks in dotnet runtime.
  absl::Status RenodeHandleMainMessage(::renode::ProtocolMessage* msg);
  absl::Status RenodeHandleSenderMessage(::renode::ProtocolMessage* msg);
  absl::Status RenodeHandleReceive(::renode::ProtocolMessage* msg);

  // 'extern "C"' entry points exported by the Peripheral DLL. First Renode
  // loads the DLL, then it resolves and calls these functions.
  friend void ::renode::initialize_native();
  friend void ::renode::initialize_context(const char* context);
  friend void ::renode::handle_request(::renode::ProtocolMessage* request);
  friend void ::renode::reset_peripheral();
  friend void ::renode::renode_external_attach__ActionIntPtr__HandleMainMessage(
      ::renode::ProtocolMessageHandler* fn);
  friend void ::renode::
      renode_external_attach__ActionIntPtr__HandleSenderMessage(
          ::renode::ProtocolMessageHandler* fn);
  friend void ::renode::renode_external_attach__ActionIntPtr__Receive(
      ::renode::ProtocolMessageHandler* fn);

  // Aforementioned 'extern "C"' functions offload actual work to the
  // class methods below.
  void CApiInitializeNative();
  void CApiInitializeContext(const char* context);
  void CApiHandleRequest(::renode::ProtocolMessage* request);
  void CApiResetPeripheral();
  void CApiAttachHandleMainMessage(
      ::renode::ProtocolMessageHandler* handle_main_message_fn);
  void CApiAttachHandleSenderMessage(
      ::renode::ProtocolMessageHandler* handle_sender_message_fn);
  void CApiAttachReceive(::renode::ProtocolMessageHandler* receive_fn);

 private:
  explicit SharedLibConnection(bool redirect_logs = false);
  ~SharedLibConnection() override = default;

  std::string context_;
  std::unique_ptr<generic::IPeripheral> peripheral_;

  absl::StatusOr<::renode::ProtocolMessage> ReceiveResponse();

  absl::Status HandleTick();
  absl::Status HandleRead(::renode::ProtocolMessage* req);
  absl::Status HandleWrite(::renode::ProtocolMessage* req);

  ::renode::ProtocolMessageHandler* renode_handle_main_message_fn_{nullptr};
  ::renode::ProtocolMessageHandler* renode_handle_sender_message_fn_{nullptr};
  ::renode::ProtocolMessageHandler* renode_receive_fn_{nullptr};

  std::unique_ptr<generic::LogRedirector> log_redirector_;
};

}  // namespace xls::simulation::renode

#endif  // XLS_SIMULATION_RENODE_SHAREDLIBCONNECTION_H_
