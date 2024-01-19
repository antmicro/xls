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

#include "xls/simulation/generic/axi_stream_like_dma_endpoint.h"

#include <memory>
#include <utility>
#include <vector>

#include "absl/strings/str_format.h"
#include "absl/strings/str_join.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/status_macros.h"
#include "xls/simulation/generic/idmaendpoint.h"

namespace xls::simulation::generic {

AxiStreamLikeDmaEndpoint::AxiStreamLikeDmaEndpoint(
    std::unique_ptr<IAxiStreamLike> stream)
    : stream_(std::move(stream)) {
  num_symbols_ = stream_->GetNumSymbols();
  symbol_size_ = stream_->GetSymbolSize();
  XLS_CHECK(symbol_size_ > 0);
  XLS_CHECK(num_symbols_ > 0);
}

size_t AxiStreamLikeDmaEndpoint::FifoSpaceLeft() const {
  return stream_->FifoCapacity() - stream_->FifoCount();
}

absl::Status AxiStreamLikeDmaEndpoint::Write(const Payload& payload) {
  XLS_CHECK(!IsReadStream());
  auto num_symbols_to_write = payload.size / symbol_size_;
  if (payload.size % symbol_size_) {
    return absl::InvalidArgumentError(absl::StrFormat(
        "Invalid transfer size: %u bytes, must be multiple of %u", payload.size,
        symbol_size_));
  }
  if (num_symbols_to_write > num_symbols_) {
    return absl::InvalidArgumentError(
        absl::StrFormat("Transfer too big: %u bytes, max is %u", payload.size,
                        symbol_size_ * num_symbols_));
  }
  // Set TLAST
  stream_->SetLast(payload.last);
  // Set TKEEP
  stream_->SetDataValid(0, num_symbols_to_write);
  // Set data
  for (uint64_t i = 0; i < (num_symbols_ * symbol_size_); i++) {
    if (i < payload.size) {
      XLS_RETURN_IF_ERROR(stream_->SetPayloadData8(i, payload.DataConst()[i]));
    } else {
      XLS_RETURN_IF_ERROR(stream_->SetPayloadData8(i, 0));
    }
  }
  XLS_RETURN_IF_ERROR(stream_->Transfer());
  return absl::OkStatus();
}

absl::Status AxiStreamLikeDmaEndpoint::Read(Payload& payload) {
  XLS_CHECK(IsReadStream());
  XLS_RETURN_IF_ERROR(stream_->Transfer());
  // Get TLAST
  payload.last = stream_->GetLast();
  // Get TKEEP
  auto tkeep = stream_->GetDataValid();
  if (tkeep.first != 0) {
    XLS_LOG(WARNING) << "Non-contiguous tkeep block. Symbols will be ignored";
    tkeep.second = 0;
  }
  uint64_t xfer_nbytes = (tkeep.second - tkeep.first) * symbol_size_;
  payload.size = xfer_nbytes;
  XLS_CHECK_LE(xfer_nbytes, payload.Capacity());
  for (uint64_t i = 0; i < xfer_nbytes; i++) {
    XLS_ASSIGN_OR_RETURN(payload.Data()[i], stream_->GetPayloadData8(i));
  }
  return absl::OkStatus();
}

}  // namespace xls::simulation::generic
