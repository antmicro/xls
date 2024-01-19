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

#include "xls/simulation/generic/streamdmachannel.h"

#include <algorithm>

#include "absl/strings/str_format.h"
#include "xls/common/bits_util.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/status_macros.h"
#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/idmaendpoint.h"

namespace xls::simulation::generic {

StreamDmaChannel::StreamDmaChannel(std::unique_ptr<IDmaEndpoint> endpoint,
                                   IConnection* connection)
    : endpoint_(std::move(endpoint)),
      transfer_base_address_(0),
      max_transfer_length_(0),
      transferred_length_(0),
      irq_mask_(0),
      dma_run_(false),
      dma_finished_(false),
      dma_discard_(true),
      irq_(0),
      connection_(connection) {
  this->element_size_ = endpoint_->GetElementSize();
}

void StreamDmaChannel::SetTransferBaseAddress(channel_addr_t address) {
  if (dma_run_) {
    XLS_LOG(WARNING) << "Base address can't be modified while DMA is running";
    return;
  }
  transfer_base_address_ = address;
}

void StreamDmaChannel::SetMaxTransferLength(uint64_t length) {
  if (dma_run_) {
    XLS_LOG(WARNING)
        << "Max transfer length can't be modified while DMA is running";
    return;
  }
  if (length % element_size_ != 0) {
    XLS_LOG(WARNING) << "Max transfer length will be clipped to: "
                     << length - (length % element_size_);
  }
  length -= length % element_size_;
  max_transfer_length_ = length;
}

void StreamDmaChannel::StartDmaRun() {
  transferred_length_ = 0;
  queued_length_ = 0;
  dma_run_ = true;
  xfer_last_ = false;
}

void StreamDmaChannel::SetControlRegister(uint64_t update_state) {
  // First 2 bits are used for IRQ masking
  irq_mask_ = update_state & kCsrIrqMaskMask;
  // Third bit enables/resets DMA
  bool new_dma_run =
      static_cast<bool>((update_state >> kCsrDmaRunShift) & kCsrDmaRunMask);
  if (!new_dma_run) {
    // transferred_length_ = 0;
    // queued_length_ = 0;
    dma_finished_ = false;
  }

  if (new_dma_run) {
    StartDmaRun();
  } else {
    dma_run_ = false;
  }
  // Sixth bit controls if DMA should discard read data
  bool new_dma_discard_n = static_cast<bool>(
      (update_state >> kCsrDmaDiscardNShift) & kCsrDmaDiscardNMask);
  dma_discard_ = !new_dma_discard_n;
}

uint64_t StreamDmaChannel::GetControlRegister() {
  uint64_t intermediate_cr_ = irq_mask_ & kCsrIrqMaskMask;
  intermediate_cr_ |= static_cast<uint64_t>(dma_run_) << kCsrDmaRunShift;
  intermediate_cr_ |= static_cast<uint64_t>(dma_finished_)
                      << kCsrDmaFinishedShift;
  intermediate_cr_ |= static_cast<uint64_t>(endpoint_->IsReadStream())
                      << kCsrIsReadStreamShift;
  intermediate_cr_ |= static_cast<uint64_t>(!dma_discard_)
                      << kCsrDmaDiscardNShift;
  intermediate_cr_ |= static_cast<uint64_t>(endpoint_->IsReady())
                      << kCsrIsReadyShift;
  return intermediate_cr_;
}

bool StreamDmaChannel::GetIRQ() { return (irq_mask_ & irq_) != 0u; }

void StreamDmaChannel::WriteXferCompletion::operator()() {
  XLS_CHECK(status == CompletionStatus::PENDING);

  chan->transferred_length_ += length;

  if (last) {
    chan->xfer_last_ = true;
    chan->dma_finished_ = true;
    chan->irq_ |= kReceivedLastIrq;
  }

  // If all the requested data has been transferred, or the transfer has been
  // prematurely marked as complete by the Update function, signal the end of
  // the transfer
  if (chan->transferred_length_ >= chan->max_transfer_length_ ||
      chan->dma_finished_) {
    chan->dma_finished_ = true;
    chan->irq_ |= kTransferFinishedIrq;
  }

  chan->ReturnPayloadBufferToPool(std::move(payload));

  status = CompletionStatus::DONE;
}

StreamDmaChannel::ReadXferCompletion::ReadXferCompletion(
    StreamDmaChannel& chan_, Payload&& payload_, uint64_t length_,
    uint64_t buf_sz)
    : chan(&chan_),
      payload(std::move(payload_)),
      length(length_),
      status(CompletionStatus::PENDING) {
  payload.size = buf_sz;
}

void StreamDmaChannel::ReadXferCompletion::operator()() {
  XLS_CHECK(status == CompletionStatus::PENDING);

  status = CompletionStatus::DELIVERED;

  chan->CompleteDeliveredReadXfersOrdered();
}

void StreamDmaChannel::TransferCompleteUpdate(uint64_t length) {
  transferred_length_ += length;
  XLS_CHECK(transferred_length_ <= queued_length_);

  if (xfer_last_) {
    dma_finished_ = true;
    irq_ |= kReceivedLastIrq;
  }

  // If all the requested data has been transferred, or the transfer has been
  // prematurely marked as complete by the Update function, signal the end of
  // the transfer
  if (transferred_length_ >= max_transfer_length_ || dma_finished_) {
    dma_finished_ = true;
    irq_ |= kTransferFinishedIrq;
  }
}

void StreamDmaChannel::CompleteDeliveredReadXfersOrdered() {
  // We need to ensure that the endpoint receives completed xfers in the right
  // order. Any contiguous prefix of 'DELIVERED' transfers will be fed into the
  // channel and the corresponding buffers will be freed. We ignore a prefix of
  // 'DONE' transfers when we are looking for 'DELIVERED' prefix, as 'DONE'
  // transfers are just waiting there to be swept back into the pool with
  // `CleanupFinishedReadXfers`.

  auto after_done =
      std::find_if(read_completions_.begin(), read_completions_.end(),
                   [](const auto& completion) -> bool {
                     return completion.status != CompletionStatus::DONE;
                   });
  auto after_delivered = std::find_if(
      after_done, read_completions_.end(), [](const auto& completion) -> bool {
        return completion.status != CompletionStatus::DELIVERED;
      });

  std::for_each(after_done, after_delivered, [this](auto& completion) {
    TransferCompleteUpdate(completion.length);

    completion.payload.last = transferred_length_ >= max_transfer_length_;
    if (transferred_length_ >= max_transfer_length_) {
      completion.payload.last = true;
      xfer_last_ = true;
    }

    // Endpoint should be ready or we wouldn't be queued.
    XLS_CHECK_OK(endpoint_->Write(completion.payload));

    ReturnPayloadBufferToPool(std::move(completion.payload));

    completion.status = CompletionStatus::DONE;
  });
}

absl::Status StreamDmaChannel::QueueWriteXfer(uint64_t addr, uint64_t length,
                                              IDmaEndpoint::Payload&& payload,
                                              bool last) {
  WriteXferCompletion& xfer_completion =
      write_completions_.emplace_back(*this, std::move(payload), length, last);

  queued_length_ += length;

  return connection_->RequestWritePeripheralToMem(
      addr, length, xfer_completion.payload.DataConst(),
      IConnection::make_callback(xfer_completion));
}

absl::Status StreamDmaChannel::QueueReadXfer(uint64_t addr, uint64_t length,
                                             Payload&& payload,
                                             uint64_t buf_sz) {
  ReadXferCompletion& xfer_completion =
      read_completions_.emplace_back(*this, std::move(payload), length, buf_sz);

  queued_length_ += length;

  return connection_->RequestReadMemToPeripheral(
      addr, length, xfer_completion.payload.Data(),
      IConnection::make_callback(xfer_completion));
}

void StreamDmaChannel::CleanupFinishedWriteXfers() {
  // Clean up all transfers that have been completed.
  write_completions_.erase(
      write_completions_.begin(),
      std::find_if(
          write_completions_.begin(), write_completions_.end(),
          [](const auto& e) { return e.status != CompletionStatus::DONE; }));
}

void StreamDmaChannel::CleanupFinishedReadXfers() {
  // Clean up all transfers that have been completed.
  read_completions_.erase(
      read_completions_.begin(),
      std::find_if(
          read_completions_.begin(), read_completions_.end(),
          [](const auto& e) { return e.status != CompletionStatus::DONE; }));
}

IDmaEndpoint::Payload StreamDmaChannel::TakePayloadBufferFromPool() {
  if (payload_pool_.empty()) {
    return endpoint_->MakePayloadWithSafeCapacity();
  }

  Payload payload = std::move(payload_pool_.back());
  payload_pool_.pop_back();
  return payload;
}

void StreamDmaChannel::ReturnPayloadBufferToPool(
    IDmaEndpoint::Payload&& payload) {
  payload_pool_.emplace_back(std::move(payload));
}

absl::Status StreamDmaChannel::UpdateWriteToEmulator() {
  CleanupFinishedWriteXfers();

  while (endpoint_->IsReady() && (queued_length_ < max_transfer_length_) &&
         !xfer_last_) {
    Payload payload = TakePayloadBufferFromPool();

    XLS_RETURN_IF_ERROR(endpoint_->Read(payload));

    auto received_size = payload.size;
    XLS_CHECK_EQ(received_size % element_size_, 0);

    uint64_t n_bytes_to_transfer =
        std::min(received_size, max_transfer_length_ - queued_length_);

    xfer_last_ = payload.last;

    if (dma_discard_) {
      TransferCompleteUpdate(n_bytes_to_transfer);
    } else {
      auto resp =
          QueueWriteXfer(transfer_base_address_ + queued_length_,
                         n_bytes_to_transfer, std::move(payload), xfer_last_);

      if (received_size > queued_length_) {  // Won't happen (tkeep)
        XLS_LOG(WARNING) << absl::StreamFormat(
            "Endpoint returned %u bytes, but only %u will be transferred to "
            "the memory to obey the max DMA transfer size set by the user (%u"
            " bytes). Data will be lost.",
            received_size, queued_length_, max_transfer_length_);
      }
    }
  }

  return absl::OkStatus();
}

absl::Status StreamDmaChannel::UpdateReadFromEmulator() {
  CleanupFinishedReadXfers();

  uint64_t max_bytes_per_transfer =
      element_size_ * endpoint_->GetMaxElementsPerTransfer();

  XLS_LOG(INFO) << "FIFO space left: " << endpoint_->FifoSpaceLeft();
  XLS_LOG(INFO) << "QueuedReadXfersCount: " << QueuedReadXfersCount();
  XLS_LOG(INFO) << "Max xfer len: " << max_transfer_length_;
  while (endpoint_->FifoSpaceLeft() - QueuedReadXfersCount()) {
    XLS_LOG(INFO) << "loop, queued len: " << queued_length_
                  << ", last: " << xfer_last_;
    if ((queued_length_ >= max_transfer_length_) || xfer_last_) {
      break;
    }

    uint64_t n_bytes_to_transfer =
        std::min(max_bytes_per_transfer, max_transfer_length_ - queued_length_);

    auto resp = QueueReadXfer(transfer_base_address_ + queued_length_,
                              n_bytes_to_transfer, TakePayloadBufferFromPool(),
                              max_bytes_per_transfer);
    // We need to clean-up the transfers in case the completion of the transfer
    // we just queued already happened. Otherwise we will misjudge the available
    // FIFO space.
    CleanupFinishedReadXfers();
  }

  XLS_CHECK_LE(read_completions_.size(), 4);

  return absl::OkStatus();
}

absl::Status StreamDmaChannel::Update() {
  if (dma_run_ && !dma_finished_) {
    if (endpoint_->IsReadStream()) {
      XLS_RETURN_IF_ERROR(UpdateWriteToEmulator());
    } else {
      XLS_RETURN_IF_ERROR(UpdateReadFromEmulator());
    }
  }
  return absl::OkStatus();
}

}  // namespace xls::simulation::generic
