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

#include "xls/simulation/generic/stream_dma_endpoint.h"

#include "absl/strings/str_format.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/status_macros.h"

namespace xls::simulation::generic {

size_t StreamDmaEndpoint::FifoSpaceLeft() const {
  return stream_->FifoCapacity() - stream_->FifoCount();
}

absl::Status StreamDmaEndpoint::Write(const Payload& payload) {
  XLS_CHECK(!IsReadStream());
  if (payload.size == 0) {
    // Empty writes are ignored
    return absl::OkStatus();
  }
  if (payload.size != transfer_size_) {
    return absl::InvalidArgumentError(
        absl::StrFormat("Invalid transfer size: %u bytes, must be %u",
                        payload.size, transfer_size_));
  }
  for (uint64_t i = 0; i < transfer_size_; i++) {
    XLS_RETURN_IF_ERROR(stream_->SetPayloadData8(i, payload.DataConst()[i]));
  }

  XLS_LOG(INFO) << "Writing payload to an endpoint.";

  XLS_RETURN_IF_ERROR(stream_->Transfer());
  return absl::OkStatus();
}

absl::Status StreamDmaEndpoint::Read(Payload& payload) {
  XLS_CHECK(IsReadStream());
  XLS_RETURN_IF_ERROR(stream_->Transfer());
  XLS_CHECK_LE(transfer_size_, payload.Capacity());
  payload.size = transfer_size_;
  for (uint64_t i = 0; i < transfer_size_; i++) {
    XLS_ASSIGN_OR_RETURN(payload.Data()[i], stream_->GetPayloadData8(i));
  }

  XLS_LOG(INFO) << "Read payload from an endpoint.";

  return absl::OkStatus();
}

}  // namespace xls::simulation::generic
