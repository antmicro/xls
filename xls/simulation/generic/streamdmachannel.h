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

#ifndef XLS_SIMULATION_GENERIC_STREAMDMACHANNEL_H_
#define XLS_SIMULATION_GENERIC_STREAMDMACHANNEL_H_

#include <memory>
#include <utility>

#include "absl/status/status.h"
#include "iconnection.h"
#include "idmaendpoint.h"
#include "xls/simulation/generic/common.h"
#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/idmaendpoint.h"

namespace xls::simulation::generic {

class StreamDmaChannel final {
 public:
  using channel_addr_t = uint64_t;

  // Control and status register
  // 63       7       6             5            4            3       2        0
  // ┌────────┬───────┬─────────────┬────────────┬────────────┬───────┬────────┐
  // │(unused)│IsReady│DMA discard N│IsReadStream│DMA finished│DMA run│IRQ mask│
  // └────────┴───────┴─────────────┴────────────┴────────────┴───────┴────────┘
  //
  // IRQ mask - (control) masks IRQ sources
  // DMA run - (control) enables/resets DMA
  // DMA finished - (status) set to 1 when transfered all data
  // IsReadStream - (status) informs whether underlying stream can be read
  // DMA discard - (control) when 0, performs the transfer through channel but
  // doesn't read the transfered data
  // IsReady - (status) set to 1 when the stream is ready to perform a single
  // transfer
  static const uint64_t kTransferFinishedIrq = 1;
  static const uint64_t kReceivedLastIrq = 2;
  static const uint64_t kCsrIrqMaskMask = 0b11;
  static const uint64_t kCsrDmaRunShift = 2;
  static const uint64_t kCsrDmaRunMask = 0b1;
  static const uint64_t kCsrDmaFinishedShift = 3;
  static const uint64_t kCsrIsReadStreamShift = 4;
  static const uint64_t kCsrDmaDiscardNShift = 5;
  static const uint64_t kCsrDmaDiscardNMask = 0b1;
  static const uint64_t kCsrIsReadyShift = 6;

  StreamDmaChannel(std::unique_ptr<IDmaEndpoint> endpoint,
                   IConnection* connection);

  StreamDmaChannel(StreamDmaChannel&& other) = default;
  StreamDmaChannel& operator=(StreamDmaChannel&& other_) = default;

  void SetTransferBaseAddress(channel_addr_t address);
  channel_addr_t GetTransferBaseAddress() {
    return this->transfer_base_address_;
  }

  void SetMaxTransferLength(uint64_t length);
  uint64_t GetMaxTransferLength() { return this->max_transfer_length_; }

  uint64_t GetTransferredLength() { return this->transferred_length_; }

  void ClearIRQReg(uint64_t reset_vector) { this->irq_ &= ~reset_vector; }
  uint64_t GetIRQReg() { return this->irq_; }

  void SetControlRegister(uint64_t update_state);
  uint64_t GetControlRegister();

  absl::Status Update();

  bool GetIRQ();
  absl::Status UpdateIRQ() { return absl::OkStatus(); }

 protected:
  std::unique_ptr<IDmaEndpoint> endpoint_;
  virtual absl::Status UpdateReadFromEmulator();
  virtual absl::Status UpdateWriteToEmulator();
  void StartDmaRun();

 private:
  friend class StreamDmaChannelPrivateAccess;

  using Payload = IDmaEndpoint::Payload;

  enum class CompletionStatus : uint8_t {
    PENDING,    // Transfer has been requested, but has not finished.
    DELIVERED,  // Transfer has finished but has not been commited to the
                // channel
    DONE,       // Transfer is fully complete, request structures can be freed.
  };

  struct WriteXferCompletion final {
    explicit WriteXferCompletion(StreamDmaChannel& chan_, Payload&& payload_,
                                 uint64_t length_, bool last_)
        : chan(&chan_),
          payload(std::move(payload_)),
          length(length_),
          last(last_),
          status(CompletionStatus::PENDING) {}

    StreamDmaChannel* chan;
    Payload payload;
    uint64_t length;
    bool last;

    CompletionStatus status;

    void operator()();
  };

  struct ReadXferCompletion final {
    explicit ReadXferCompletion(StreamDmaChannel& chan_, Payload&& payload_,
                                uint64_t length_, uint64_t buf_sz);

    StreamDmaChannel* chan;
    Payload payload;
    uint64_t length;

    CompletionStatus status;

    void operator()();
  };

  std::deque<Payload> payload_pool_;

  std::deque<WriteXferCompletion> write_completions_;
  std::deque<ReadXferCompletion> read_completions_;

  absl::Status QueueWriteXfer(uint64_t addr, uint64_t length, Payload&& payload,
                              bool last);
  absl::Status QueueReadXfer(uint64_t addr, uint64_t length, Payload&& payload,
                             uint64_t buf_sz);
  size_t QueuedReadXfersCount() { return read_completions_.size(); }

  void CleanupFinishedWriteXfers();
  void CleanupFinishedReadXfers();

  Payload TakePayloadBufferFromPool();
  void ReturnPayloadBufferToPool(Payload&& payload);

  channel_addr_t transfer_base_address_;
  uint64_t max_transfer_length_;
  uint64_t transferred_length_;
  uint64_t queued_length_;

  bool xfer_last_;

  // Control and status register fields
  uint64_t irq_mask_;
  bool dma_run_;
  bool dma_finished_;
  bool dma_discard_;

  void TransferCompleteUpdate(uint64_t length);

  void CompleteDeliveredReadXfersOrdered();

  uint64_t irq_;
  uint64_t element_size_;
  IConnection* connection_;
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_STREAMDMACHANNEL_H_
