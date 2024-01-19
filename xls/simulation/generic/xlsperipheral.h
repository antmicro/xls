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

#ifndef XLS_SIMULATION_GENERIC_XLSPERIPHERAL_H_
#define XLS_SIMULATION_GENERIC_XLSPERIPHERAL_H_

#include <memory>
#include <string_view>
#include <vector>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "xls/simulation/generic/iaxistreamlike.h"
#include "xls/simulation/generic/ir_single_value.h"
#include "xls/simulation/generic/ichannelmanager.h"
#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/iperipheral.h"
#include "xls/simulation/generic/istream.h"
#include "xls/simulation/generic/runtime_manager.h"
#include "xls/simulation/generic/runtime_status.h"

namespace xls::simulation::generic {

class XlsPeripheral final : public IPeripheral {
 public:
  XlsPeripheral() = delete;
  XlsPeripheral(const XlsPeripheral&) = delete;
  XlsPeripheral& operator=(const XlsPeripheral&) = delete;
  XlsPeripheral(XlsPeripheral&&) = default;

  class RegisterChannelManagerOps {
   public:
    absl::StatusOr<std::unique_ptr<RuntimeStatus>> WrapStatusRegister();
    absl::StatusOr<std::unique_ptr<IRSingleValue>> WrapIrSingleValue(
        std::string_view name);
    absl::StatusOr<std::unique_ptr<IStream>> WrapIStream(std::string_view name);
    absl::StatusOr<std::unique_ptr<IAxiStreamLike>> WrapIAxiStreamLike(
        std::string_view name, uint64_t data, std::optional<uint64_t> tkeep,
        std::optional<uint64_t> tlast);

    absl::Status RegisterChannelManager(
        std::unique_ptr<IChannelManager>&& manager);

   private:
    explicit RegisterChannelManagerOps(XlsPeripheral& peripheral)
        : peripheral_(peripheral) {}

    XlsPeripheral& peripheral_;

    friend class XlsPeripheral;
  };

  // using RegisterChannelManager =
  // std::function<absl::Status(IChannelManager*)>;
  using ChannelManagerFactory = std::function<absl::Status(RegisterChannelManagerOps&)>;

  static absl::StatusOr<XlsPeripheral> Make(
      std::unique_ptr<Package>&& package, IConnection& connection,
      ChannelManagerFactory&& channel_manager_factory);

  absl::Status CheckRequest(uint64_t addr, AccessWidth width) override;
  absl::StatusOr<uint64_t> HandleRead(uint64_t addr,
                                      AccessWidth width) override;
  absl::Status HandleWrite(uint64_t addr, AccessWidth width,
                           uint64_t payload) override;
  absl::Status HandleTick() override;
  absl::Status Reset() override;

  uint64_t CalculateSize() const override;

 private:
  XlsPeripheral(IConnection& connection, std::unique_ptr<Package> package,
                std::unique_ptr<RuntimeManager> runtime,
                ChannelManagerFactory&& channel_manager_factory);

  bool last_irq_;
  // Config config_;
  IConnection& connection_;
  std::unique_ptr<Package> package_;
  std::unique_ptr<RuntimeManager> runtime_;
  std::vector<std::unique_ptr<IChannelManager>> managers_;
  ChannelManagerFactory channel_manager_factory_;
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_XLSPERIPHERAL_H_
