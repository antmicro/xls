#include "xls/simulation/gem5/gem5connection.h"

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_format.h"
#include "gem5connection.h"
#include "xls/common/logging/logging.h"
#include "xls/simulation/generic/config.h"
#include "xls/simulation/generic/iperipheral.h"
#include "xls/simulation/generic/peripheral_factory.h"
#include "xls/simulation/generic/xlsperipheral.h"

#define _C __attribute__((sysv_abi))

namespace xls::simulation::gem5 {

#include "xls/simulation/gem5/gem5api.h"

static C_DmaResponseOps ConvertDMACallback(
    const Gem5Connection::OnRequestCompletionCB& cb) {
  return C_DmaResponseOps{
      .ctx = cb.ctx,
      .transfer_complete = cb.complete,
  };
}

static C_XlsCallbacks XlsCallbacks;

Gem5Connection::Gem5Connection() : log_redirector_(*this, true) {}

Gem5Connection& Gem5Connection::Instance() {
  static Gem5Connection inst{};
  return inst;
}

absl::Status Gem5Connection::Log(absl::LogSeverity level,
                                 std::string_view msg) {
  if (!XlsCallbacks.xls_log) {
    printf("XLS UNINIT-LOG (%d): %s\n", static_cast<int>(level), msg.data());
    return absl::OkStatus();
  }
  XlsCallbacks.xls_log(XlsCallbacks.ctx, static_cast<int>(level), msg.data());
  return absl::OkStatus();
}

absl::Status Gem5Connection::RequestReadMemToPeripheral(
    uint64_t address, size_t count, uint8_t* buf,
    OnRequestCompletionCB on_complete) {
  if (!XlsCallbacks.xls_dmaMemToDev) {
    return absl::InternalError("gem5 not initialized.");
  }
  XlsCallbacks.xls_dmaMemToDev(XlsCallbacks.ctx, address, count, buf,
                               ConvertDMACallback(on_complete));

  return absl::OkStatus();
}

absl::Status Gem5Connection::RequestWritePeripheralToMem(
    uint64_t address, size_t count, const uint8_t* buf,
    OnRequestCompletionCB on_complete) {
  if (!XlsCallbacks.xls_dmaMemToDev) {
    return absl::InternalError("gem5 not initialized.");
  }
  XlsCallbacks.xls_dmaDevToMem(XlsCallbacks.ctx, address, count, buf,
                               ConvertDMACallback(on_complete));
  return absl::OkStatus();
}

absl::Status Gem5Connection::SetInterrupt(uint64_t num, bool state) {
  if (!XlsCallbacks.xls_requestIRQ) {
    return absl::InternalError("gem5 not initialized.");
  }
  XlsCallbacks.xls_requestIRQ(XlsCallbacks.ctx, num, state ? 1 : 0);
  return absl::OkStatus();
}

}  // namespace xls::simulation::gem5

// namespace generic = xls::simulation::generic;
using xls::simulation::gem5::Gem5Connection;
using xls::simulation::generic::PeripheralFactory;
using xls::simulation::generic::XlsPeripheral;

namespace api = xls::simulation::gem5;

static void c_error(const api::C_ErrorOps* error_ops, int severity,
                    std::string&& msg) {
  if (error_ops) {
    error_ops->reportError(error_ops->ctx, severity, msg.c_str());
  } else {
    printf("FATAL (%d): %s\n", severity, msg.c_str());
    XLS_LOG(FATAL) << "An unhandled error has occured in XLS: " << msg;
  }
}

#define C_ERROR(error_ops, severity, ...) \
  c_error(error_ops, severity, absl::StrFormat(__VA_ARGS__))

extern "C" int _C xls_initCallbacks(api::C_XlsCallbacks callbacks) {
  xls::simulation::gem5::XlsCallbacks = callbacks;
  return 0;
}

extern "C" api::C_XlsPeripheralH _C
xls_setupPeripheral(const char* config, api::C_ErrorOps* error_ops) {
  XLS_LOG(INFO) << "In " << __func__;
  auto peripheral_opt =
      PeripheralFactory::Instance().Make(Gem5Connection::Instance(), config);
  if (!peripheral_opt.ok()) {
    C_ERROR(error_ops, 1, "Failed to set XLS peripheral: %s\n",
            peripheral_opt.status().ToString().c_str());
    return nullptr;
  }
  return peripheral_opt.value().release();
}

extern "C" int _C xls_resetPeripheral(api::C_XlsPeripheralH peripheral_h,
                                      api::C_ErrorOps* error_ops) {
  auto* peripheral = static_cast<XlsPeripheral*>(peripheral_h);

  absl::Status result = peripheral->Reset();
  if (!result.ok()) {
    C_ERROR(error_ops, 3, "Failed to reset peripheral: %s",
            result.message().data());
    return -1;
  }

  XLS_LOG(INFO) << "Peripheral has been reset!";

  return 0;
}

extern "C" void _C xls_destroyPeripheral(api::C_XlsPeripheralH peripheral_h,
                                         api::C_ErrorOps*) {
  delete static_cast<XlsPeripheral*>(peripheral_h);
}

extern "C" size_t _C xls_getPeripheralSize(api::C_XlsPeripheralH peripheral_h,
                                           api::C_ErrorOps* error_ops) {
  XlsPeripheral* peripheral = static_cast<XlsPeripheral*>(peripheral_h);

  return peripheral->CalculateSize();
}

extern "C" int _C xls_updatePeripheral(api::C_XlsPeripheralH peripheral_h,
                                       api::C_ErrorOps* error_ops) {
  XlsPeripheral* peripheral = static_cast<XlsPeripheral*>(peripheral_h);

  auto result = peripheral->HandleTick();
  if (!result.ok()) {
    C_ERROR(error_ops, 3, "An error has occured when ticking the device: %s",
            result.message().data());
    return -1;
  }

  return 0;
}

template <AccessWidth Width, typename T>
static int p_xls_read(api::C_XlsPeripheralH peripheral_h, uint64_t address,
                      T* buf, api::C_ErrorOps* error_ops) {
  XlsPeripheral* peripheral = static_cast<XlsPeripheral*>(peripheral_h);

  auto value = peripheral->HandleRead(address, Width);
  if (!value.ok()) {
    C_ERROR(error_ops, 1, "Read operation failed: %s\n",
            value.status().ToString().c_str());
    return 1;
  }

  auto result = peripheral->HandleTick();
  if (!result.ok()) {
    C_ERROR(error_ops, 3,
            "An error has occured when updating peripheral "
            "(read): %s",
            result.message().data());
    return -1;
  }

  *buf = static_cast<T>(*value);
  return 0;
}

extern "C" int _C xls_readByte(api::C_XlsPeripheralH peripheral_h,
                               uint64_t address, uint8_t* buf,
                               api::C_ErrorOps* error_ops) {
  return p_xls_read<AccessWidth::BYTE>(peripheral_h, address, buf, error_ops);
}

extern "C" int _C xls_readWord(api::C_XlsPeripheralH peripheral_h,
                               uint64_t address, uint16_t* buf,
                               api::C_ErrorOps* error_ops) {
  return p_xls_read<AccessWidth::WORD>(peripheral_h, address, buf, error_ops);
}

extern "C" int _C xls_readDWord(api::C_XlsPeripheralH peripheral_h,
                                uint64_t address, uint32_t* buf,
                                api::C_ErrorOps* error_ops) {
  return p_xls_read<AccessWidth::DWORD>(peripheral_h, address, buf, error_ops);
}

extern "C" int _C xls_readQWord(api::C_XlsPeripheralH peripheral_h,
                                uint64_t address, uint64_t* buf,
                                api::C_ErrorOps* error_ops) {
  return p_xls_read<AccessWidth::QWORD>(peripheral_h, address, buf, error_ops);
}

template <AccessWidth Width, typename T>
static int p_xls_write(api::C_XlsPeripheralH peripheral_h, uint64_t address,
                       T buf, api::C_ErrorOps* error_ops) {
  XlsPeripheral* peripheral = static_cast<XlsPeripheral*>(peripheral_h);

  absl::Status result = peripheral->HandleWrite(address, Width, buf);

  if (!result.ok()) {
    C_ERROR(error_ops, 1, "Write operation failed: %s\n",
            result.ToString().c_str());
    return 1;
  }

  result = peripheral->HandleTick();
  if (!result.ok()) {
    C_ERROR(error_ops, 3,
            "An error has occured when updating peripheral "
            "(write): %s",
            result.message().data());
    return -1;
  }

  return 0;
}

extern "C" int _C xls_writeByte(api::C_XlsPeripheralH peripheral_h,
                                uint64_t address, uint8_t buf,
                                api::C_ErrorOps* error_ops) {
  return p_xls_write<AccessWidth::BYTE>(peripheral_h, address, buf, error_ops);
}

extern "C" int _C xls_writeWord(api::C_XlsPeripheralH peripheral_h,
                                uint64_t address, uint16_t buf,
                                api::C_ErrorOps* error_ops) {
  return p_xls_write<AccessWidth::WORD>(peripheral_h, address, buf, error_ops);
}

extern "C" int _C xls_writeDWord(api::C_XlsPeripheralH peripheral_h,
                                 uint64_t address, uint32_t buf,
                                 api::C_ErrorOps* error_ops) {
  return p_xls_write<AccessWidth::DWORD>(peripheral_h, address, buf, error_ops);
}

extern "C" int _C xls_writeQWord(api::C_XlsPeripheralH peripheral_h,
                                 uint64_t address, uint64_t buf,
                                 api::C_ErrorOps* error_ops) {
  return p_xls_write<AccessWidth::QWORD>(peripheral_h, address, buf, error_ops);
}
