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

#include "xls/simulation/renode/sharedlibconnection.h"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "absl/log/log.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "sharedlibconnection.h"
#include "xls/common/logging/log_flags.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/ret_check.h"
#include "xls/simulation/generic/iperipheral.h"
#include "xls/simulation/generic/peripheral_factory.h"
#include "xls/simulation/renode/renode_protocol.h"
#include "xls/simulation/renode/renode_protocol_native.h"

namespace xls::simulation::renode {
namespace generic = xls::simulation::generic;

static bool RedirectOnInstantiation = true;

SharedLibConnection::SharedLibConnection(bool redirect_logs)
    : log_redirector_(std::make_unique<generic::LogRedirector>(
          *this, RedirectOnInstantiation)) {}

SharedLibConnection& SharedLibConnection::Instance() {
  static SharedLibConnection inst{};
  return inst;
}

void SharedLibConnection::SetLogRedirection(bool on) {
  RedirectOnInstantiation = on;
  if (on) {
    Instance().log_redirector_->Enable();
  } else {
    Instance().log_redirector_->Disable();
  }
}

absl::StatusOr<::renode::ProtocolMessage>
SharedLibConnection::ReceiveResponse() {
  ::renode::ProtocolMessage msg{};
  auto status = RenodeHandleReceive(&msg);
  if (!status.ok()) {
    return status;
  }
  return msg;
}

absl::Status SharedLibConnection::Log(absl::LogSeverity level,
                                      std::string_view msg) {
  // Map from XLS log level onto Renode log level
  ::renode::LogLevel renode_lvl;

  switch (level) {
    case absl::LogSeverity::kInfo:
      renode_lvl = ::renode::LOG_LEVEL_INFO;
      break;
    case absl::LogSeverity::kWarning:
      renode_lvl = ::renode::LOG_LEVEL_WARNING;
      break;
    case absl::LogSeverity::kError:
    case absl::LogSeverity::kFatal:
    default:
      renode_lvl = ::renode::LOG_LEVEL_ERROR;
      break;
  }

  std::string str{msg};
  // Renode logMessage protocol specifies two messages:
  // 1st - send cstring message (addr=str.size(), data=str.c_str())
  // 2nd - send log level (addr=0, data=renode_lvl)
  ::renode::ProtocolMessage packet;
  packet = ::renode::ProtocolMessage{::renode::logMessage, str.size(),
                                     reinterpret_cast<uint64_t>(str.c_str())};
  XLS_RETURN_IF_ERROR(RenodeHandleSenderMessage(&packet));
  packet = ::renode::ProtocolMessage{::renode::logMessage, 0,
                                     static_cast<uint64_t>(renode_lvl)};
  return RenodeHandleSenderMessage(&packet);
}

absl::Status SharedLibConnection::RenodeHandleMainMessage(
    ::renode::ProtocolMessage* msg) {
  if (!renode_handle_main_message_fn_) {
    return absl::InternalError(
        "renode_handle_main_message_fn_ is null. Renode didn't call attacher?");
  }
  renode_handle_main_message_fn_(msg);
  return absl::OkStatus();
}

absl::Status SharedLibConnection::RenodeHandleSenderMessage(
    ::renode::ProtocolMessage* msg) {
  if (!renode_handle_sender_message_fn_) {
    return absl::InternalError(
        "renode_handle_sender_message_fn_ is null. Renode didn't call "
        "attacher?");
  }
  renode_handle_sender_message_fn_(msg);
  return absl::OkStatus();
}

absl::Status SharedLibConnection::RenodeHandleReceive(
    ::renode::ProtocolMessage* msg) {
  if (!renode_receive_fn_) {
    return absl::InternalError(
        "renode_receive_fn_ is null. Renode didn't call attacher?");
  }
  renode_receive_fn_(msg);
  return absl::OkStatus();
}

void SharedLibConnection::CApiInitializeContext(const char* context) {
  context_ = std::string{context};
}

void SharedLibConnection::CApiInitializeNative() {
  // Instantiate peripheral using factory
  auto peripheral_opt = generic::PeripheralFactory::Instance().Make(*this, context_);
  if (!peripheral_opt.ok()) {
    XLS_LOG(FATAL) << "Failed to initialize XLS peripheral";
  }
  peripheral_ = std::move(peripheral_opt.value());
}

static ::renode::ProtocolMessage FormReadRequest(uint64_t address,
                                                 AccessWidth width) {
  int actionId;

  switch (width) {
    case AccessWidth::BYTE:
      actionId = ::renode::Action::getByte;
      break;
    case AccessWidth::WORD:
      actionId = ::renode::Action::getWord;
      break;
    case AccessWidth::DWORD:
      actionId = ::renode::Action::getDoubleWord;
      break;
    case AccessWidth::QWORD:
      actionId = ::renode::Action::getQuadWord;
      break;
    default:
      XLS_LOG(FATAL) << absl::StreamFormat("Unhandled AccessWidth: %d", width);
      break;
  }

  return ::renode::ProtocolMessage(actionId, address, 0);
}

static ::renode::ProtocolMessage FormWriteRequest(uint64_t address,
                                                  uint64_t payload,
                                                  AccessWidth width) {
  int actionId;
  switch (width) {
    case AccessWidth::BYTE:
      actionId = ::renode::Action::pushByte;
      break;
    case AccessWidth::WORD:
      actionId = ::renode::Action::pushWord;
      break;
    case AccessWidth::DWORD:
      actionId = ::renode::Action::pushDoubleWord;
      break;
    case AccessWidth::QWORD:
      actionId = ::renode::Action::pushQuadWord;
      break;
    default:
      XLS_LOG(FATAL) << absl::StreamFormat("Unhandled AccessWidth: %d", width);
      break;
  }

  return ::renode::ProtocolMessage(actionId, address, payload);
}

static absl::Status CheckResponse(::renode::ProtocolMessage resp,
                                  ::renode::Action expected) {
  if (resp.actionId == ::renode::Action::error)
    return absl::InternalError("Read request unsuccessful");

  if (resp.actionId != expected)
    return absl::UnimplementedError(
        absl::StrFormat("Unexpected response: %d", resp.actionId));

  return absl::OkStatus();
}

absl::Status SharedLibConnection::RequestReadMemToPeripheral(
    uint64_t address, size_t count, uint8_t* buf,
    OnRequestCompletionCB on_complete) {
  uint64_t cursor = address;

  while (count >= sizeof(uint64_t)) {
    auto req = FormReadRequest(cursor, AccessWidth::QWORD);
    XLS_CHECK_OK(RenodeHandleSenderMessage(&req));

    auto resp = ReceiveResponse();
    XLS_CHECK_OK(resp.status());
    XLS_CHECK_OK(CheckResponse(resp.value(), ::renode::Action::writeRequest));

    uint64_t value = resp.value().value;
    // Assumption: little-endian arch
    memcpy(buf, &value, sizeof(uint64_t));

    count -= sizeof(uint64_t);
    cursor += sizeof(uint64_t);
    buf += sizeof(uint64_t);
  }

  while (count >= sizeof(uint8_t)) {
    auto req = FormReadRequest(cursor, AccessWidth::BYTE);
    XLS_CHECK_OK(RenodeHandleSenderMessage(&req));

    auto resp = ReceiveResponse();
    XLS_CHECK_OK(resp.status());
    XLS_CHECK_OK(CheckResponse(resp.value(), ::renode::Action::writeRequest));

    *buf = resp.value().value;

    count -= sizeof(uint8_t);
    cursor += sizeof(uint8_t);
    buf += sizeof(uint8_t);
  }

  on_complete.complete(on_complete.ctx);

  return absl::OkStatus();
}

absl::Status SharedLibConnection::RequestWritePeripheralToMem(
    uint64_t address, size_t count, const uint8_t* buf,
    OnRequestCompletionCB on_complete) {
  uint64_t cursor = address;

  while (count >= sizeof(uint64_t)) {
    uint64_t data;
    // Assumption: little-endian arch
    memcpy(&data, buf, sizeof(uint64_t));
    auto req = FormWriteRequest(cursor, data, AccessWidth::QWORD);
    XLS_CHECK_OK(RenodeHandleSenderMessage(&req));

    count -= sizeof(uint64_t);
    cursor += sizeof(uint64_t);
    buf += sizeof(uint64_t);
  }

  while (count >= sizeof(uint8_t)) {
    auto req = FormWriteRequest(cursor, *buf, AccessWidth::BYTE);
    XLS_CHECK_OK(RenodeHandleSenderMessage(&req));

    count -= sizeof(uint8_t);
    cursor += sizeof(uint8_t);
    buf += sizeof(uint8_t);
  }

  on_complete.complete(on_complete.ctx);

  return absl::OkStatus();
}

absl::Status SharedLibConnection::SetInterrupt(uint64_t num, bool state) {
  ::renode::ProtocolMessage req =
      state ? ::renode::ProtocolMessage{::renode::Action::interrupt, num, 1}
            : ::renode::ProtocolMessage{::renode::Action::interrupt, num, 0};

  return RenodeHandleSenderMessage(&req);
}

absl::Status SharedLibConnection::HandleTick() {
  XLS_RETURN_IF_ERROR(peripheral_->HandleTick());

  ::renode::ProtocolMessage req{::renode::Action::tickClock, 0, 0};
  XLS_CHECK_OK(RenodeHandleSenderMessage(&req));

  return absl::OkStatus();
}

static AccessWidth RenodeActionToAccessWidth(::renode::Action access_action) {
  // All read and write actions have continuous IDs and are sorted by type
  // (r/w) and then by width. So, we can take ID's their offset relative to
  // the first action and do a mod 4 (equivalent to & 0x3) to get the width
  // identifier.
  switch (access_action) {
    case ::renode::Action::readRequestByte:
    case ::renode::Action::writeRequestByte:
      return AccessWidth::BYTE;
    case ::renode::Action::readRequestWord:
    case ::renode::Action::writeRequestWord:
      return AccessWidth::WORD;
    case ::renode::Action::readRequestDoubleWord:
    case ::renode::Action::writeRequestDoubleWord:
      return AccessWidth::DWORD;
    case ::renode::Action::readRequestQuadWord:
    case ::renode::Action::writeRequestQuadWord:
      return AccessWidth::QWORD;
    default:
      XLS_LOG(ERROR) << "Unhandled Renode access action!";
      XLS_DCHECK(false);
  }
  return AccessWidth::BYTE;
}

absl::Status SharedLibConnection::HandleRead(::renode::ProtocolMessage* req) {
  AccessWidth access =
      RenodeActionToAccessWidth(static_cast<::renode::Action>(req->actionId));
  XLS_RETURN_IF_ERROR(peripheral_->CheckRequest(req->addr, access));
  auto payload = peripheral_->HandleRead(req->addr, access);

  XLS_RETURN_IF_ERROR(peripheral_->HandleTick());

  if (payload.ok()) {
    ::renode::ProtocolMessage req{::renode::Action::ok, 0, *payload};
    XLS_CHECK_OK(RenodeHandleMainMessage(&req));
  }

  return payload.status();
}

absl::Status SharedLibConnection::HandleWrite(::renode::ProtocolMessage* req) {
  AccessWidth access =
      RenodeActionToAccessWidth(static_cast<::renode::Action>(req->actionId));
  XLS_RETURN_IF_ERROR(peripheral_->CheckRequest(req->addr, access));
  auto status = peripheral_->HandleWrite(req->addr, access, req->value);

  XLS_RETURN_IF_ERROR(peripheral_->HandleTick());

  if (status.ok()) {
    ::renode::ProtocolMessage req{::renode::Action::ok, 0, 0};
    XLS_CHECK_OK(RenodeHandleMainMessage(&req));
  }

  return status;
}

void SharedLibConnection::CApiHandleRequest(
    ::renode::ProtocolMessage* request) {
  XLS_CHECK(peripheral_)
      << "HandleRequest() called on uninitialized peripheral";
  absl::Status op_status = absl::OkStatus();

  switch (request->actionId) {
    case ::renode::Action::tickClock:
      op_status = HandleTick();
      break;
    case ::renode::Action::resetPeripheral:
      op_status = peripheral_->Reset();
      break;
    case ::renode::Action::writeRequestByte:
    case ::renode::Action::writeRequestWord:
    case ::renode::Action::writeRequestDoubleWord:
    case ::renode::Action::writeRequestQuadWord:
      op_status = HandleWrite(request);
      break;
    case ::renode::Action::readRequestByte:
    case ::renode::Action::readRequestWord:
    case ::renode::Action::readRequestDoubleWord:
    case ::renode::Action::readRequestQuadWord:
      op_status = HandleRead(request);
      break;
    default:
      op_status =
          Log(absl::LogSeverity::kError,
              absl::StrFormat("Unsupported action: %d", request->actionId));
      if (!op_status.ok()) {
        break;
      }
      ::renode::ProtocolMessage req{::renode::Action::error, 0, 0};
      op_status = RenodeHandleMainMessage(&req);
      break;
  }

  if (!op_status.ok()) {
    XLS_LOG(ERROR) << "Operation failed: " << op_status.ToString();
    ::renode::ProtocolMessage req{::renode::Action::error, 0, 0};
    XLS_CHECK_OK(RenodeHandleMainMessage(&req));
  }
}

void SharedLibConnection::CApiResetPeripheral() {
  XLS_CHECK(peripheral_)
      << "ResetPeripheral() called on uninitialized peripheral";
  XLS_CHECK_OK(peripheral_->Reset());
}

void SharedLibConnection::CApiAttachHandleMainMessage(
    ::renode::ProtocolMessageHandler* handle_main_message_fn) {
  renode_handle_main_message_fn_ = handle_main_message_fn;
}

void SharedLibConnection::CApiAttachHandleSenderMessage(
    ::renode::ProtocolMessageHandler* handle_sender_message_fn) {
  renode_handle_sender_message_fn_ = handle_sender_message_fn;
}

void SharedLibConnection::CApiAttachReceive(
    ::renode::ProtocolMessageHandler* receive_fn) {
  renode_receive_fn_ = receive_fn;
}

}  // namespace xls::simulation::renode

// Implementation of 'extern "C"' DLL entry points called directly by Renode
namespace renode {

using xls::simulation::renode::SharedLibConnection;

// Implementation of Renode C API
extern "C" void initialize_native() {
  SharedLibConnection::Instance().CApiInitializeNative();
}

extern "C" void initialize_context(const char* context) {
  SharedLibConnection::Instance().CApiInitializeContext(context);
}

extern "C" void handle_request(ProtocolMessage* request) {
  SharedLibConnection::Instance().CApiHandleRequest(request);
}

extern "C" void reset_peripheral() {
  SharedLibConnection::Instance().CApiResetPeripheral();
}

extern "C" void renode_external_attach__ActionIntPtr__HandleMainMessage(
    ProtocolMessageHandler fn) {
  SharedLibConnection::Instance().CApiAttachHandleMainMessage(fn);
}

extern "C" void renode_external_attach__ActionIntPtr__HandleSenderMessage(
    ProtocolMessageHandler fn) {
  SharedLibConnection::Instance().CApiAttachHandleSenderMessage(fn);
}

extern "C" void renode_external_attach__ActionIntPtr__Receive(
    ProtocolMessageHandler fn) {
  SharedLibConnection::Instance().CApiAttachReceive(fn);
}

}  // namespace renode
