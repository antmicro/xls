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

#include "xls/simulation/generic/peripheral_factory.h"

#include "absl/status/statusor.h"

#include <functional>
#include <memory>
#include <string_view>
#include <utility>

#include "iconnection.h"
#include "singlevaluemanager.h"
#include "streammanager.h"
#include "xls/common/file/filesystem.h"
#include "xls/ir/ir_parser.h"
#include "xls/simulation/generic/axi_stream_like_dma_endpoint.h"
#include "xls/simulation/generic/config.h"
#include "xls/simulation/generic/dmastreammanager.h"
#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/iperipheral.h"
#include "xls/simulation/generic/ir_stream.h"
#include "xls/simulation/generic/singlevaluemanager.h"
#include "xls/simulation/generic/stream_dma_endpoint.h"
#include "xls/simulation/generic/streammanager.h"
#include "xls/simulation/generic/xlsperipheral.h"

namespace xls::simulation::generic {

PeripheralFactory& PeripheralFactory::Instance() {
  static PeripheralFactory inst{};
  return inst;
}

// Load config file
// Assumptions: text proto, IR simulation
absl::StatusOr<Config> LoadConfig(std::string_view context) {
  ConfigType config_type = ConfigType::kTextproto;
  SimulationType sim_type = SimulationType::kIR;

  auto proto = MakeProtoForConfigFile(context, config_type);
  if (!proto.ok()) {
    return absl::InternalError(
        absl::StrFormat("Error loading config file '%s': %s", context,
                        proto.status().ToString()));
  }
  return Config(std::move(proto.value()), sim_type);
}

absl::StatusOr<std::unique_ptr<Package>> LoadPackage(const Config& config) {
  // Describe the config
  XLS_ASSIGN_OR_RETURN(std::filesystem::path design_path,
                       config.GetDesignPath());
  XLS_LOG(INFO) << "Setting up simulation of the following design: "
                << design_path;

  XLS_ASSIGN_OR_RETURN(std::string design_contents,
                       xls::GetFileContents(design_path));

  auto package = xls::Parser::ParsePackage(design_contents);
  if (!package.ok()) {
    XLS_LOG(FATAL) << "Failed to parse package " << design_path
                   << "\n Reason: " << package.status();
  }
  return std::move(package.value());
}

using RegisterChannelManagerOps = XlsPeripheral::RegisterChannelManagerOps;

static absl::StatusOr<std::optional<SingleValueManager>>
SetUpSingleValueManager(const Config& config, RegisterChannelManagerOps ops) {
  absl::StatusOr<std::optional<ConfigSingleValueManager>> svm_config =
      config.GetSingleValueManagerConfig();
  if (!svm_config.ok()) {
    XLS_LOG(WARNING) << "Error loading SingleValue configuration: "
                     << svm_config.status().ToString();
    return std::nullopt;
  }
  if (!svm_config->has_value()) {
    return std::nullopt;
  }

  SingleValueManager svm(svm_config->value().GetBaseAddress());
  XLS_ASSIGN_OR_RETURN(auto status_reg, ops.WrapStatusRegister());
  XLS_RETURN_IF_ERROR(svm.RegisterChannel(
      std::move(status_reg), svm_config->value().GetRuntimeStatusOffset()));

  for (auto& ch_config : svm_config->value().GetChannels()) {
    std::string_view ch_name = ch_config.GetName();

    XLS_ASSIGN_OR_RETURN(auto singlevalue, ops.WrapIrSingleValue(ch_name));

    XLS_ASSIGN_OR_RETURN(uint64_t offset, ch_config.GetOffset());

    XLS_LOG(INFO) << "Registering single value channel \"" << ch_name << "\"";
    XLS_RETURN_IF_ERROR(svm.RegisterChannel(std::move(singlevalue), offset));
  }

  return svm;
}

absl::StatusOr<std::optional<StreamManager>> SetUpStreamManager(
    const Config& config, RegisterChannelManagerOps ops) {
  absl::StatusOr<std::optional<ConfigStreamManager>> sm_config =
      config.GetStreamManagerConfig();
  if (!sm_config.ok()) {
    XLS_LOG(WARNING) << "Error loading Stream configuration: "
                     << sm_config.status().ToString();
    return std::nullopt;
  }
  if (!sm_config->has_value()) {
    return std::nullopt;
  }

  absl::StatusOr<StreamManager> sm = StreamManager::Build(
      sm_config->value().GetBaseAddress(),
      [&](const auto& RegisterStream) -> absl::Status {
        for (auto& ch_config : sm_config->value().GetChannels()) {
          std::string_view ch_name = ch_config.GetName();

          XLS_ASSIGN_OR_RETURN(auto stream, ops.WrapIStream(ch_name));

          XLS_ASSIGN_OR_RETURN(IChannelManager::channel_addr_t offset,
                               ch_config.GetOffset());

          XLS_LOG(INFO) << "Registering channel \"" << ch_name << "\"";
          RegisterStream(offset, stream.release());
        }
        return absl::OkStatus();
      });
  if (!sm.ok()) {
    return sm.status();
  }
  return std::make_optional(std::move(sm.value()));
}

static absl::StatusOr<std::optional<DmaStreamManager>> SetUpDmaStreamManager(
    IConnection* connection, const Config& config,
    RegisterChannelManagerOps ops) {
  // DMA Stream Manager not declared in config, skip it
  absl::StatusOr<std::optional<ConfigStreamManager>> dma_config =
      config.GetDmaStreamManagerConfig();
  if (!dma_config.ok()) {
    XLS_LOG(WARNING) << "Error loading DMA configuration: "
                     << dma_config.status().ToString();
    return std::nullopt;
  }
  if (!dma_config->has_value()) {
    return std::nullopt;
  }

  DmaStreamManager dma = DmaStreamManager(dma_config->value().GetBaseAddress());
  for (auto& ch_config : dma_config->value().GetChannels()) {
    XLS_ASSIGN_OR_RETURN(auto stream, ops.WrapIStream(ch_config.GetName()));
    XLS_ASSIGN_OR_RETURN(uint64_t dma_id, ch_config.GetDMAID());
    XLS_RETURN_IF_ERROR(
        dma.RegisterEndpoint(std::unique_ptr<StreamDmaEndpoint>(
                                 new StreamDmaEndpoint(std::move(stream))),
                             dma_id, connection));
  }

  return dma;
}

static absl::StatusOr<std::optional<DmaStreamManager>> SetUpDmaAXIStreamManager(
    IConnection* connection, const Config& config,
    RegisterChannelManagerOps ops) {
  // AXI DMA Stream Manager not declared in config, skip it
  absl::StatusOr<std::optional<ConfigDmaAxiStreamLikeManager>> dma_config =
      config.GetDmaAxiStreamLikeManagerConfig();
  if (!dma_config.ok()) {
    XLS_LOG(WARNING) << "Error loading AXI DMA configuration: "
                     << dma_config.status().ToString();
    return std::nullopt;
  }
  if (!dma_config->has_value()) {
    return std::nullopt;
  }

  DmaStreamManager dma = DmaStreamManager(dma_config->value().GetBaseAddress());
  for (auto& ch_config : dma_config->value().GetChannels()) {
    std::optional<uint64_t> tkeep_index = std::nullopt;
    if (ch_config.GetKeepIdx().ok()) {
      tkeep_index = ch_config.GetKeepIdx().value();
    }
    std::optional<uint64_t> tlast_index = std::nullopt;
    if (ch_config.GetLastIdx().ok()) {
      tlast_index = ch_config.GetLastIdx().value();
    }

    uint64_t data_index = ch_config.GetDataIdxs()[0];

    XLS_LOG(INFO) << "Registering AXIDMA channel " << ch_config.GetName();

    XLS_ASSIGN_OR_RETURN(auto stream,
                         ops.WrapIAxiStreamLike(ch_config.GetName(), data_index,
                                                tkeep_index, tlast_index));
    XLS_ASSIGN_OR_RETURN(uint64_t dma_id, ch_config.GetDMAID());
    XLS_RETURN_IF_ERROR(dma.RegisterEndpoint(
        std::unique_ptr<AxiStreamLikeDmaEndpoint>(
            new AxiStreamLikeDmaEndpoint(std::move(stream))),
        dma_id, connection));
  }

  return dma;
}

template <typename Manager, typename SetupProc>
static absl::Status RegisterChannelManager(RegisterChannelManagerOps& ops,
                                           SetupProc setup) {
  XLS_ASSIGN_OR_RETURN(auto manager_option, setup());
  if (manager_option.has_value()) {
    XLS_CHECK_OK(ops.RegisterChannelManager(std::unique_ptr<Manager>(
        new Manager(std::move(manager_option.value())))));
  }
}

struct XlsPeripheralInitFromConfig {
  std::shared_ptr<Config> config;
  IConnection& connection;

  absl::Status operator()(RegisterChannelManagerOps& ops) {
    XLS_ASSIGN_OR_RETURN(auto sv_option,
                         SetUpSingleValueManager(*config.get(), ops));
    if (sv_option.has_value()) {
      XLS_CHECK_OK(
          ops.RegisterChannelManager(std::unique_ptr<SingleValueManager>(
              new SingleValueManager(std::move(sv_option.value())))));
    }

    XLS_ASSIGN_OR_RETURN(auto sm_option,
                         SetUpStreamManager(*config.get(), ops));
    if (sm_option.has_value()) {
      XLS_CHECK_OK(ops.RegisterChannelManager(std::unique_ptr<StreamManager>(
          new StreamManager(std::move(sm_option.value())))));
    }

    XLS_ASSIGN_OR_RETURN(auto dsm_option, SetUpDmaStreamManager(
                                              &connection, *config.get(), ops));
    if (dsm_option.has_value()) {
      XLS_CHECK_OK(ops.RegisterChannelManager(std::unique_ptr<DmaStreamManager>(
          new DmaStreamManager(std::move(dsm_option.value())))));
    }

    XLS_ASSIGN_OR_RETURN(
        auto dasm_option,
        SetUpDmaAXIStreamManager(&connection, *config.get(), ops));
    if (dasm_option.has_value()) {
      XLS_CHECK_OK(ops.RegisterChannelManager(std::unique_ptr<DmaStreamManager>(
          new DmaStreamManager(std::move(dasm_option.value())))));
    }

    return absl::OkStatus();
  }
};

PeripheralFactory::PeripheralFactory() {
  // Default behavior - create XlsPeripheral, can be modified by calling
  // OverrideFactoryMethod.
  make_ = [](IConnection& connection, std::string_view context)
      -> absl::StatusOr<std::unique_ptr<IPeripheral>> {
    absl::StatusOr<Config> config = LoadConfig(context);
    if (!config.ok()) {
      return absl::InternalError(absl::StrFormat("Failed to load config: %s",
                                                 config.status().message()));
    }

    absl::StatusOr<std::unique_ptr<Package>> package =
        LoadPackage(config.value());
    if (!package.ok()) {
      return absl::InternalError(absl::StrFormat("Failed to load package: %s",
                                                 package.status().message()));
    }

    auto peripheral = XlsPeripheral::Make(
        std::move(package.value()), connection,
        XlsPeripheralInitFromConfig{
            std::make_shared<Config>(std::move(config.value())), connection});

    if (!peripheral.ok()) {
      return absl::InternalError(
          absl::StrFormat("Failed to build XLS peripheral. Reason: %s",
                          peripheral.status().message()));
    }
    return std::make_unique<XlsPeripheral>(std::move(peripheral.value()));
  };
}

absl::StatusOr<std::unique_ptr<IPeripheral>> PeripheralFactory::Make(
    IConnection& connection, std::string_view context) {
  return make_(connection, context);
}

void PeripheralFactory::OverrideFactoryMethod(
    std::function<PeripheralFactory::FactoryMethod> func) {
  make_ = std::move(func);
}

}  // namespace xls::simulation::generic
