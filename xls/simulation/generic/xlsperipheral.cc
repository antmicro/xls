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

#include "xls/simulation/generic/xlsperipheral.h"

#include <cstdint>
#include <initializer_list>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

#include "absl/status/status.h"
#include "absl/strings/str_format.h"
#include "xls/simulation/generic/ir_stream.h"
#include "xls/common/file/filesystem.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/ret_check.h"
#include "xls/ir/package.h"
#include "xls/simulation/generic/ichannelmanager.h"
#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/ir_axistreamlike.h"

namespace xls::simulation::generic {

absl::StatusOr<XlsPeripheral> XlsPeripheral::Make(
    std::unique_ptr<Package>&& package, IConnection& connection,
    ChannelManagerFactory&& channel_manager_factory) {
  XLS_LOG(INFO) << "Creating generic::XlsPeripheral.";

  // Real init happens on `Reset` call.
  return XlsPeripheral(connection, std::move(package), nullptr,
                       std::move(channel_manager_factory));
}

uint64_t XlsPeripheral::CalculateSize() const {
  uint64_t max_sz = 0;
  for (const auto& manager : managers_) {
    uint64_t man_end = manager->GetBaseAddress() + manager->GetSize();
    max_sz = man_end > max_sz ? man_end : max_sz;
  }
  return max_sz;
}

XlsPeripheral::XlsPeripheral(IConnection& connection,
                             std::unique_ptr<Package> package,
                             std::unique_ptr<RuntimeManager> runtime,
                             ChannelManagerFactory&& channel_manager_factory)
    : connection_(connection),
      package_(std::move(package)),
      runtime_(std::move(runtime)),
      channel_manager_factory_(std::move(channel_manager_factory)) {}

uint64_t GetByteWidth(AccessWidth access) {
  switch (access) {
    case AccessWidth::BYTE:
      return 1;
    case AccessWidth::WORD:
      return 2;
    case AccessWidth::DWORD:
      return 4;
    case AccessWidth::QWORD:
      return 8;
    default:
      XLS_LOG(ERROR) << "Unhandled AccessWidth!";
      XLS_DCHECK(false);
  }
  return 0;
}

absl::Status XlsPeripheral::CheckRequest(uint64_t addr, AccessWidth width) {
  if (runtime_ == nullptr) {
    XLS_LOG(FATAL) << "Device has not been initialized";
    return absl::FailedPreconditionError("Device has not been initialized");
  }

  uint64_t access_width = GetByteWidth(width);
  bool in_range = false;
  bool possible_unaligned = false;

  for (auto& manager : managers_) {
    if (manager->InRange(addr) && manager->InRange(addr + access_width - 1)) {
      in_range = true;
      break;
    }
    if (manager->InRange(addr)) {
      in_range = true;
    }
    if (manager->InRange(addr + access_width - 1)) {
      possible_unaligned = true;
    }
    if (in_range && possible_unaligned) {
      return absl::InvalidArgumentError(
          "Access to multiple managers at once is not supported");
    }
  }

  if (!in_range) {
    return absl::InvalidArgumentError(
        absl::StrFormat("Access at %016x - has no mapping", addr));
  }
  return absl::OkStatus();
}

absl::StatusOr<uint64_t> XlsPeripheral::HandleRead(uint64_t addr,
                                                   AccessWidth width) {
  for (auto& manager : managers_) {
    if (manager->InRange(addr)) {
      switch (width) {
        case AccessWidth::BYTE:
          return manager->ReadU8AtAddress(addr);
        case AccessWidth::WORD:
          return manager->ReadU16AtAddress(addr);
        case AccessWidth::DWORD:
          return manager->ReadU32AtAddress(addr);
        case AccessWidth::QWORD:
          return manager->ReadU64AtAddress(addr);
      }
    }
  }

  XLS_LOG(WARNING) << absl::StreamFormat("Access to unmapped region: 0x%08x",
                                         addr);

  return 0;
}

absl::Status XlsPeripheral::HandleWrite(uint64_t addr, AccessWidth width,
                                        uint64_t payload) {
  absl::Status status;
  for (auto& manager : managers_) {
    if (manager->InRange(addr)) {
      switch (width) {
        case AccessWidth::BYTE:
          status = manager->WriteU8AtAddress(addr, payload);
          break;
        case AccessWidth::WORD:
          status = manager->WriteU16AtAddress(addr, payload);
          break;
        case AccessWidth::DWORD:
          status = manager->WriteU32AtAddress(addr, payload);
          break;
        case AccessWidth::QWORD:
          status = manager->WriteU64AtAddress(addr, payload);
          break;
      }
    }
  }
  return status;
}

absl::Status XlsPeripheral::HandleTick() {
  if (runtime_ == nullptr) {
    XLS_LOG(FATAL) << "Device has not been initialized";
    return absl::FailedPreconditionError("Device has not been initialized");
  }

  absl::Status tick_status;
  tick_status = runtime_->Update();
  // This is horrible, but in order to avoid it we would have to change the
  // way ProcRuntime::Tick() reports deadlocks. Those are almost never
  // errors in case of co-simulation, instead they usually mean that the
  // device is idle (not in use).
  if (!tick_status.ok()) {
    if (tick_status.message().find_first_of("Proc network is deadlocked.") !=
        0) {
      XLS_LOG(FATAL) << tick_status.message();
      return tick_status;
    }
  }

  bool irq = false;

  for (auto& manager : managers_) {
    if (auto s = manager->Update(); !s.ok()) {
      XLS_LOG(FATAL) << s.message();
      return s;
    }

    irq |= manager->GetIRQ();
  }

  if (last_irq_ != irq) {
    last_irq_ = irq;
    return connection_.SetInterrupt(0, irq);
  }

  return absl::OkStatus();
}

absl::Status XlsPeripheral::Reset() {
  this->managers_.clear();

  auto runtime_man = RuntimeManager::Create(package_.get(), false);
  if (!runtime_man.ok()) {
    return absl::InternalError("Failed to initialize runtime: " +
                               runtime_man.status().ToString());
  }

  this->runtime_ = std::move(runtime_man.value());

  last_irq_ = false;

  RegisterChannelManagerOps setup_ops(*this);
  auto status = this->channel_manager_factory_(setup_ops);

  return status;
}

absl::Status XlsPeripheral::RegisterChannelManagerOps::RegisterChannelManager(
    std::unique_ptr<IChannelManager>&& manager) {
  peripheral_.managers_.emplace_back(std::move(manager));

  // TODO: Chek for overlapping manager regions
  return absl::OkStatus();
}

absl::StatusOr<std::unique_ptr<RuntimeStatus>>
XlsPeripheral::RegisterChannelManagerOps::WrapStatusRegister() {
  return std::make_unique<RuntimeStatus>(peripheral_.runtime_->Status());
}

absl::StatusOr<std::unique_ptr<IRSingleValue>>
XlsPeripheral::RegisterChannelManagerOps::WrapIrSingleValue(
    std::string_view name) {
  XLS_ASSIGN_OR_RETURN(
      auto* queue,
      peripheral_.runtime_->Runtime().queue_manager().GetQueueByName(name));

  if (queue->channel()->kind() != ChannelKind::kSingleValue) {
    return absl::InternalError(
        absl::StrFormat("Channel \"%s\" is not a register.", name));
  }

  XLS_ASSIGN_OR_RETURN(IRSingleValue singlevalue,
                       IRSingleValue::MakeIRSingleValue(queue));

  return std::make_unique<IRSingleValue>(std::move(singlevalue));
}

absl::StatusOr<std::unique_ptr<IStream>>
XlsPeripheral::RegisterChannelManagerOps::WrapIStream(std::string_view name) {
  XLS_ASSIGN_OR_RETURN(
      auto* queue,
      peripheral_.runtime_->Runtime().queue_manager().GetQueueByName(name));

  if (queue->channel()->kind() != ChannelKind::kStreaming) {
    return absl::InternalError(
        absl::StrFormat("Channel \"%s\" is not a stream.", name));
  }

  XLS_ASSIGN_OR_RETURN(IRStream stream, IRStream::MakeIRStream(queue));
  return std::unique_ptr<IRStream>(new IRStream(std::move(stream)));
}

absl::StatusOr<std::unique_ptr<IAxiStreamLike>>
XlsPeripheral::RegisterChannelManagerOps::WrapIAxiStreamLike(
    std::string_view name, uint64_t data, std::optional<uint64_t> tkeep,
    std::optional<uint64_t> tlast) {
  XLS_ASSIGN_OR_RETURN(
      auto* queue,
      peripheral_.runtime_->Runtime().queue_manager().GetQueueByName(name));

  if (queue->channel()->kind() != ChannelKind::kStreaming) {
    return absl::InternalError(
        absl::StrFormat("Channel \"%s\" is not a stream.", name));
  }

  XLS_ASSIGN_OR_RETURN(
      IrAxiStreamLike stream,
      IrAxiStreamLike::Make(queue, tkeep.has_value(), data, tlast, tkeep));

  return std::unique_ptr<IAxiStreamLike>(
      new IrAxiStreamLike(std::move(stream)));
}

}  // namespace xls::simulation::generic
