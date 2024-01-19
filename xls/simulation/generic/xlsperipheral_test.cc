// Copyright 2024 The XLS Authors
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
#include <functional>
#include <memory>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "gmock/gmock.h"
#include "gtest/gtest.h"
#include "xls/common/status/matchers.h"
#include "xls/ir/package.h"
#include "xls/simulation/generic/common.h"
#include "xls/simulation/generic/ichannelmanager.h"
#include "xls/simulation/generic/iconnection.h"

namespace xls::simulation::generic {
namespace {

using channel_addr_t = IChannelManager::channel_addr_t;

class ChannelManagerMock final : public IChannelManager {
 public:
  ChannelManagerMock(uint64_t base_address, uint64_t size)
      : IChannelManager(base_address) {
    address_range_end_ = size;
  }

  ~ChannelManagerMock() override = default;

  MOCK_METHOD(absl::Status, WriteU8AtAddress,
              (channel_addr_t address, uint8_t data), (override));
  MOCK_METHOD(absl::Status, WriteU16AtAddress,
              (channel_addr_t address, uint16_t data), (override));
  MOCK_METHOD(absl::Status, WriteU32AtAddress,
              (channel_addr_t address, uint32_t data), (override));
  MOCK_METHOD(absl::Status, WriteU64AtAddress,
              (channel_addr_t address, uint64_t data), (override));
  MOCK_METHOD(absl::StatusOr<uint8_t>, ReadU8AtAddress,
              (channel_addr_t address), (override));
  MOCK_METHOD(absl::StatusOr<uint16_t>, ReadU16AtAddress,
              (channel_addr_t address), (override));
  MOCK_METHOD(absl::StatusOr<uint32_t>, ReadU32AtAddress,
              (channel_addr_t address), (override));
  MOCK_METHOD(absl::StatusOr<uint64_t>, ReadU64AtAddress,
              (channel_addr_t address), (override));

  MOCK_METHOD(absl::Status, Update, (), (override));

  MOCK_METHOD(bool, GetIRQ, (), (override));
};

template <typename ChanMan>
class SharedChannelManager final : public IChannelManager {
 public:
  SharedChannelManager(uint64_t base_address, uint64_t size)
      : IChannelManager(base_address),
        chan_man_(std::make_unique<ChanMan>(base_address, size)) {
    address_range_end_ = size;
  }

  ~SharedChannelManager() override = default;

  absl::Status WriteU8AtAddress(channel_addr_t address, uint8_t data) override {
    return chan_man_->WriteU8AtAddress(address, data);
  }

  absl::Status WriteU16AtAddress(channel_addr_t address,
                                 uint16_t data) override {
    return chan_man_->WriteU16AtAddress(address, data);
  }

  absl::Status WriteU32AtAddress(channel_addr_t address,
                                 uint32_t data) override {
    return chan_man_->WriteU32AtAddress(address, data);
  }

  absl::Status WriteU64AtAddress(channel_addr_t address,
                                 uint64_t data) override {
    return chan_man_->WriteU64AtAddress(address, data);
  }

  absl::StatusOr<uint8_t> ReadU8AtAddress(channel_addr_t address) override {
    return chan_man_->ReadU8AtAddress(address);
  }

  absl::StatusOr<uint16_t> ReadU16AtAddress(channel_addr_t address) override {
    return chan_man_->ReadU16AtAddress(address);
  }

  absl::StatusOr<uint32_t> ReadU32AtAddress(channel_addr_t address) override {
    return chan_man_->ReadU32AtAddress(address);
  }

  absl::StatusOr<uint64_t> ReadU64AtAddress(channel_addr_t address) override {
    return chan_man_->ReadU64AtAddress(address);
  }

  absl::Status Update() override { return chan_man_->Update(); }

  bool GetIRQ() override { return chan_man_->GetIRQ(); }

  ChanMan& ChannelManager() { return *chan_man_; }

 private:
  std::shared_ptr<ChanMan> chan_man_;
};

class ConnectionMock final : public IConnection {
 public:
  MOCK_METHOD(absl::Status, SetInterrupt, (uint64_t num, bool state),
              (override));
  
  absl::Status Log(absl::LogSeverity level, std::string_view msg) override {}

  MOCK_METHOD(absl::Status, RequestReadMemToPeripheral,
              (uint64_t address, size_t count, uint8_t* buf,
               OnRequestCompletionCB on_complete), (override));
  
  MOCK_METHOD(absl::Status, RequestWritePeripheralToMem,
              (uint64_t address, size_t count, const uint8_t* buf,
               OnRequestCompletionCB on_complete), (override));
};

using RegisterOps = XlsPeripheral::RegisterChannelManagerOps;

using ::testing::_;
using ::testing::Eq;
using ::testing::InSequence;
using ::testing::Invoke;
using ::testing::InvokeWithoutArgs;
using ::testing::Return;

using SharedChanManMock = SharedChannelManager<ChannelManagerMock>;

class XlsPeripheralTest : public ::testing::Test {
 public:
  ConnectionMock connection_;

  std::unique_ptr<Package> MakePackage() {
    return std::make_unique<Package>("test_pkg");
  }

  ~XlsPeripheralTest() override = default;
};

TEST_F(XlsPeripheralTest, InstantiateTest) {
  XLS_EXPECT_OK(XlsPeripheral::Make(
      MakePackage(), connection_,
      [](RegisterOps& ops) -> absl::Status { return absl::OkStatus(); }));
}

TEST_F(XlsPeripheralTest, ResetTest) {
  bool initialized = false;
  XLS_ASSERT_OK_AND_ASSIGN(
      XlsPeripheral peripheral,
      XlsPeripheral::Make(MakePackage(), connection_,
                          [&](RegisterOps& ops) -> absl::Status {
                            initialized = true;
                            return absl::OkStatus();
                          }));

  XLS_EXPECT_OK(peripheral.Reset());
  EXPECT_TRUE(initialized);
}

class XlsPeripheralAccessTest : public XlsPeripheralTest {
 public:
  SharedChanManMock man1_;
  SharedChanManMock man2_;

  XlsPeripheralAccessTest() : man1_(0x0, 0x0), man2_(0x0, 0x0) {}
  ~XlsPeripheralAccessTest() override = default;

  void SetUp() override {
    man1_ = SharedChanManMock(0x100, 0x10);
    man2_ = SharedChanManMock(0x300, 0x20);
  }

  XlsPeripheral MakePeripheral() {
    auto peripheral_opt = XlsPeripheral::Make(
        MakePackage(), connection_, [&](RegisterOps& ops) -> absl::Status {
          XLS_EXPECT_OK(ops.RegisterChannelManager(
              std::make_unique<SharedChanManMock>(man1_)));
          XLS_EXPECT_OK(ops.RegisterChannelManager(
              std::make_unique<SharedChanManMock>(man2_)));
          return absl::OkStatus();
        });
    XLS_EXPECT_OK(peripheral_opt);
    return std::move(peripheral_opt.value());
  }

  static void Sequencer(
      IChannelManager& man,
      const std::function<void(uint64_t, AccessWidth)>& action) {
    for (auto width : {AccessWidth::BYTE, AccessWidth::WORD, AccessWidth::DWORD,
                       AccessWidth::QWORD}) {
      for (uint64_t i = 0; i < man.GetSize(); ++i) {
        action(man.GetBaseAddress() + i, width);
      }
    }
  }
};

TEST_F(XlsPeripheralAccessTest, ReadTest) {
  XlsPeripheral peripheral = MakePeripheral();
  XLS_EXPECT_OK(peripheral.Reset());

  auto expect_access = [](ChannelManagerMock& man, uint64_t address,
                          AccessWidth access_width) {
    switch (access_width) {
      case AccessWidth::BYTE:
        EXPECT_CALL(man, ReadU8AtAddress(Eq(address)))
            .WillOnce(Return(absl::StatusOr<uint8_t>(0)));
        return;
      case AccessWidth::WORD:
        EXPECT_CALL(man, ReadU16AtAddress(Eq(address)))
            .WillOnce(Return(absl::StatusOr<uint16_t>(0)));
        return;
      case AccessWidth::DWORD:
        EXPECT_CALL(man, ReadU32AtAddress(Eq(address)))
            .WillOnce(Return(absl::StatusOr<uint32_t>(0)));
        return;
      case AccessWidth::QWORD:
        EXPECT_CALL(man, ReadU64AtAddress(Eq(address)))
            .WillOnce(Return(absl::StatusOr<uint64_t>(0)));
        return;
    }
  };

  {
    InSequence s;

    Sequencer(man1_, [&](uint64_t address, AccessWidth access_width) {
      expect_access(man1_.ChannelManager(), address, access_width);
    });

    Sequencer(man2_, [&](uint64_t address, AccessWidth access_width) {
      expect_access(man2_.ChannelManager(), address, access_width);
    });
  }

  Sequencer(man1_, [&](uint64_t address, AccessWidth access_width) {
    XLS_EXPECT_OK(peripheral.HandleRead(address, access_width));
  });

  Sequencer(man2_, [&](uint64_t address, AccessWidth access_width) {
    XLS_EXPECT_OK(peripheral.HandleRead(address, access_width));
  });
}

TEST_F(XlsPeripheralAccessTest, WriteTest) {
  XlsPeripheral peripheral = MakePeripheral();
  XLS_EXPECT_OK(peripheral.Reset());

  auto expect_access = [](ChannelManagerMock& man, uint64_t address,
                          AccessWidth access_width) {
    switch (access_width) {
      case AccessWidth::BYTE:
        EXPECT_CALL(man, WriteU8AtAddress(Eq(address), _))
            .WillOnce(Return(absl::OkStatus()));
        return;
      case AccessWidth::WORD:
        EXPECT_CALL(man, WriteU16AtAddress(Eq(address), _))
            .WillOnce(Return(absl::OkStatus()));
        return;
      case AccessWidth::DWORD:
        EXPECT_CALL(man, WriteU32AtAddress(Eq(address), _))
            .WillOnce(Return(absl::OkStatus()));
        return;
      case AccessWidth::QWORD:
        EXPECT_CALL(man, WriteU64AtAddress(Eq(address), _))
            .WillOnce(Return(absl::OkStatus()));
        return;
    }
  };

  {
    InSequence s;

    Sequencer(man1_, [&](uint64_t address, AccessWidth access_width) {
      expect_access(man1_.ChannelManager(), address, access_width);
    });

    Sequencer(man2_, [&](uint64_t address, AccessWidth access_width) {
      expect_access(man2_.ChannelManager(), address, access_width);
    });
  }

  Sequencer(man1_, [&](uint64_t address, AccessWidth access_width) {
    XLS_EXPECT_OK(peripheral.HandleWrite(address, access_width, 0));
  });

  Sequencer(man2_, [&](uint64_t address, AccessWidth access_width) {
    XLS_EXPECT_OK(peripheral.HandleWrite(address, access_width, 0));
  });
}

TEST_F(XlsPeripheralAccessTest, UpdateTest) {
  XlsPeripheral peripheral = MakePeripheral();
  XLS_EXPECT_OK(peripheral.Reset());

  EXPECT_CALL(man1_.ChannelManager(), Update());
  EXPECT_CALL(man2_.ChannelManager(), Update());

  XLS_EXPECT_OK(peripheral.HandleTick());
}

TEST_F(XlsPeripheralAccessTest, SetInterruptTest) {
  XlsPeripheral peripheral = MakePeripheral();
  XLS_EXPECT_OK(peripheral.Reset());

  bool interrupted;

  ON_CALL(man1_.ChannelManager(), GetIRQ())
      .WillByDefault(InvokeWithoutArgs([&]() -> bool { return interrupted; }));

  ON_CALL(man1_.ChannelManager(), WriteU8AtAddress(_, _))
      .WillByDefault(Invoke(([&](uint64_t addr, uint8_t data) -> absl::Status {
        interrupted = data != 0;
        return absl::OkStatus();
      })));

  {
    InSequence s;

    // Raise the interrupt
    EXPECT_CALL(man1_.ChannelManager(), WriteU8AtAddress(_, _));
    EXPECT_CALL(man1_.ChannelManager(), GetIRQ());
    EXPECT_CALL(connection_, SetInterrupt(Eq(0), Eq(true)));

    // Lower the interrupt
    EXPECT_CALL(man1_.ChannelManager(), WriteU8AtAddress(_, _));
    EXPECT_CALL(man1_.ChannelManager(), GetIRQ());
    EXPECT_CALL(connection_, SetInterrupt(Eq(0), Eq(false)));
  }

  XLS_EXPECT_OK(
      peripheral.HandleWrite(man1_.GetBaseAddress(), AccessWidth::BYTE, 1));

  XLS_EXPECT_OK(peripheral.HandleTick());

  XLS_EXPECT_OK(
      peripheral.HandleWrite(man1_.GetBaseAddress(), AccessWidth::BYTE, 0));

  XLS_EXPECT_OK(peripheral.HandleTick());
}

TEST_F(XlsPeripheralAccessTest, ResetInterruptTest) {
  XlsPeripheral peripheral = MakePeripheral();
  XLS_EXPECT_OK(peripheral.Reset());

  bool interrupted;

  ON_CALL(man1_.ChannelManager(), GetIRQ())
      .WillByDefault(InvokeWithoutArgs([&]() -> bool { return interrupted; }));

  {
    InSequence s;

    // Raise the interrupt
    EXPECT_CALL(connection_, SetInterrupt(Eq(0), Eq(true)));

    // The second call should happen after the second reset
    EXPECT_CALL(connection_, SetInterrupt(Eq(0), Eq(true)));
  }

  interrupted = false;
  XLS_EXPECT_OK(peripheral.HandleTick());

  interrupted = true;
  XLS_EXPECT_OK(peripheral.HandleTick());

  // Reset should cause the interrupt to be retriggered on the next update.
  XLS_EXPECT_OK(peripheral.Reset());
  XLS_EXPECT_OK(peripheral.HandleTick());
}

}  // namespace
}  // namespace xls::simulation::generic
