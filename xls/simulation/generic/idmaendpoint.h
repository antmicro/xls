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

#ifndef XLS_SIMULATION_GENERIC_IDMAENDPOINT_H_
#define XLS_SIMULATION_GENERIC_IDMAENDPOINT_H_

#include <cstdint>
#include <vector>

#include "absl/status/status.h"

namespace xls::simulation::generic {

// IDmaEndpoint represents a peripheral end of a 1D DMA channel.
//
// It allows to transfer a stream of fixed-size elements, and supports framing
// those elements into packets by flagging the last element of the transfer.
// User can query the size of a single element, as well as a maximum number of
// elements that a single transfer can fit. In general, transferring any number
// of elements between 0 and maximum should be supported by the implementation.
//
// Transfers with number of bytes not divisible by the element size, are deemed
// as erroneous. Empty transfers (zero bytes) are supported by the interface,
// however, an implemnentation is allowed to ignore them.
class IDmaEndpoint {
 public:
  struct Payload {
   public:
    Payload(const Payload&) = delete;
    Payload& operator=(const Payload&) = delete;
    Payload(Payload&& other)
        : size(other.size),
          last(other.last),
          data_(other.data_),
          capacity_(other.capacity_) {
      this->data_ = other.data_;
      this->capacity_ = other.capacity_;
      this->last = other.last;
      this->size = other.size;

      other.data_ = nullptr;
    }

    Payload& operator=(Payload&& other) {
      this->data_ = other.data_;
      this->capacity_ = other.capacity_;
      this->last = other.last;
      this->size = other.size;

      other.data_ = nullptr;

      return *this;
    }

    ~Payload() { delete[] data_; }

    uint8_t* Data() { return data_; }
    const uint8_t* DataConst() const { return data_; }
    size_t Capacity() { return capacity_; }

    uint64_t size;
    bool last;

   private:
    friend class IDmaEndpoint;

    explicit Payload(size_t capacity, uint64_t size_ = 0, bool last_ = false)
        : size(size_),
          last(last_),
          data_(new uint8_t[capacity]),
          capacity_(capacity) {}

    uint8_t* data_;
    size_t capacity_;
  };

  virtual ~IDmaEndpoint() = default;

  virtual uint64_t GetElementSize() const = 0;
  virtual uint64_t GetMaxElementsPerTransfer() const = 0;
  virtual bool IsReadStream() const = 0;
  virtual bool IsReady() const = 0;
  virtual size_t FifoSpaceLeft() const = 0;
  virtual absl::Status Write(const Payload& payload) = 0;
  virtual absl::Status Read(Payload& payload) = 0;

  Payload MakePayloadWithSafeCapacity() const {
    return Payload(GetElementSize() * GetMaxElementsPerTransfer());
  }
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_IDMAENDPOINT_H_
