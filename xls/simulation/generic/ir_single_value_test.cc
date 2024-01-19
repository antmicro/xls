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

#include "xls/simulation/generic/ir_single_value.h"

#include <memory>

#include "absl/status/status.h"
#include "gtest/gtest.h"
#include "xls/common/status/matchers.h"
#include "xls/interpreter/channel_queue.h"
#include "xls/ir/channel.h"
#include "xls/ir/ir_test_base.h"
#include "xls/ir/package.h"

namespace xls::simulation::generic {
namespace {

using ::testing::Optional;

class MakeIrSingleValueQueueTest : public IrTestBase {};

TEST_F(MakeIrSingleValueQueueTest, MakeIRSingleValue) {
  Package package(TestName());
  XLS_ASSERT_OK_AND_ASSIGN(
      Channel * channel,
      package.CreateSingleValueChannel("my_channel", ChannelOps::kSendReceive,
                                       package.GetBitsType(64)));
  XLS_ASSERT_OK_AND_ASSIGN(Elaboration elaboration,
                           Elaboration::ElaborateOldStylePackage(&package));
  XLS_ASSERT_OK_AND_ASSIGN(ChannelInstance * channel_inst,
                           elaboration.GetUniqueInstance(channel));

  std::unique_ptr<ChannelQueue> single_value_queue =
      std::make_unique<ChannelQueue>(channel_inst);
  EXPECT_THAT(IRSingleValue::MakeIRSingleValue(single_value_queue.get()),
              xls::status_testing::IsOk());
}

TEST_F(MakeIrSingleValueQueueTest, MakeIRSinglValueNotSingleValueChannel) {
  Package package(TestName());
  XLS_ASSERT_OK_AND_ASSIGN(
      Channel * channel,
      package.CreateStreamingChannel("my_channel", ChannelOps::kSendReceive,
                                     package.GetBitsType(64)));
  XLS_ASSERT_OK_AND_ASSIGN(Elaboration elaboration,
                           Elaboration::ElaborateOldStylePackage(&package));
  XLS_ASSERT_OK_AND_ASSIGN(ChannelInstance * channel_inst,
                           elaboration.GetUniqueInstance(channel));

  std::unique_ptr<ChannelQueue> single_value_queue =
      std::make_unique<ChannelQueue>(channel_inst);
  EXPECT_THAT(
      IRSingleValue::MakeIRSingleValue(single_value_queue.get()),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
}

class IrSingleValueQueueTest : public IrTestBase {
 protected:
  void SetUp() override {
    pkg_ = std::make_unique<Package>(TestName());
    XLS_ASSERT_OK_AND_ASSIGN(
        Channel * channel,
        pkg_->CreateSingleValueChannel("my_channel", ChannelOps::kSendReceive,
                                       this->pkg_->GetBitsType(64)));
    XLS_ASSERT_OK_AND_ASSIGN(elaboration_,
                             Elaboration::ElaborateOldStylePackage(pkg_.get()));
    XLS_ASSERT_OK_AND_ASSIGN(ChannelInstance * channel_inst,
                             elaboration_.GetUniqueInstance(channel));

    this->single_value_queue_ = std::make_unique<ChannelQueue>(channel_inst);
    this->test_obj_ = std::make_unique<IRSingleValue>(
        IRSingleValue::MakeIRSingleValue(this->single_value_queue_.get())
            .value());
  }

  std::unique_ptr<Package> pkg_;
  Elaboration elaboration_;
  std::unique_ptr<ChannelQueue> single_value_queue_;
  std::unique_ptr<IRSingleValue> test_obj_;
};

TEST_F(IrSingleValueQueueTest, GetChannelWidth) {
  EXPECT_EQ(this->test_obj_->GetChannelWidth(), 64);
}

TEST_F(IrSingleValueQueueTest, ReadByte) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->GetPayloadData8(0),
              xls::status_testing::IsOkAndHolds(0));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  XLS_ASSERT_OK(
      this->single_value_queue_->Write(Value(UBits(0xFEDCBA9876543210, 64))));
  EXPECT_THAT(this->test_obj_->GetPayloadData8(0),
              xls::status_testing::IsOkAndHolds(0x10));
  EXPECT_THAT(this->test_obj_->GetPayloadData8(0),
              xls::status_testing::IsOkAndHolds(0x10));
  EXPECT_THAT(this->test_obj_->GetPayloadData8(0),
              xls::status_testing::IsOkAndHolds(0x10));
}

TEST_F(IrSingleValueQueueTest, ReadWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->GetPayloadData16(0),
              xls::status_testing::IsOkAndHolds(0));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  XLS_ASSERT_OK(
      this->single_value_queue_->Write(Value(UBits(0xFEDCBA9876543210, 64))));
  EXPECT_THAT(this->test_obj_->GetPayloadData16(0),
              xls::status_testing::IsOkAndHolds(0x3210));
  EXPECT_THAT(this->test_obj_->GetPayloadData16(0),
              xls::status_testing::IsOkAndHolds(0x3210));
  EXPECT_THAT(this->test_obj_->GetPayloadData16(0),
              xls::status_testing::IsOkAndHolds(0x3210));
}

TEST_F(IrSingleValueQueueTest, ReadDoubleWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->GetPayloadData32(0),
              xls::status_testing::IsOkAndHolds(0));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  XLS_ASSERT_OK(
      this->single_value_queue_->Write(Value(UBits(0xFEDCBA9876543210, 64))));
  EXPECT_THAT(this->test_obj_->GetPayloadData32(0),
              xls::status_testing::IsOkAndHolds(0x76543210));
  EXPECT_THAT(this->test_obj_->GetPayloadData32(0),
              xls::status_testing::IsOkAndHolds(0x76543210));
  EXPECT_THAT(this->test_obj_->GetPayloadData32(0),
              xls::status_testing::IsOkAndHolds(0x76543210));
}

TEST_F(IrSingleValueQueueTest, ReadQuadWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->GetPayloadData64(0),
              xls::status_testing::IsOkAndHolds(0));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  XLS_ASSERT_OK(
      this->single_value_queue_->Write(Value(UBits(0xFEDCBA9876543210, 64))));
  EXPECT_THAT(this->test_obj_->GetPayloadData64(0),
              xls::status_testing::IsOkAndHolds(0xFEDCBA9876543210));
  EXPECT_THAT(this->test_obj_->GetPayloadData64(0),
              xls::status_testing::IsOkAndHolds(0xFEDCBA9876543210));
  EXPECT_THAT(this->test_obj_->GetPayloadData64(0),
              xls::status_testing::IsOkAndHolds(0xFEDCBA9876543210));
}

TEST_F(IrSingleValueQueueTest, ReadIncorrectOffsetByte) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->GetPayloadData8(16),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, ReadIncorrectOffsetWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->GetPayloadData16(16),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, ReadIncorrectOffsetDoubleWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->GetPayloadData32(16),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, ReadIncorrectOffsetQuadWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->GetPayloadData64(16),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, ReadPartialWord) {
  EXPECT_THAT(this->test_obj_->GetPayloadData16(7),
              xls::status_testing::IsOkAndHolds(0));
  XLS_ASSERT_OK(
      this->single_value_queue_->Write(Value(UBits(0xFEDCBA9876543210, 64))));
  EXPECT_THAT(this->test_obj_->GetPayloadData16(7),
              xls::status_testing::IsOkAndHolds(0xFE));
  EXPECT_THAT(this->test_obj_->GetPayloadData16(7),
              xls::status_testing::IsOkAndHolds(0xFE));
  EXPECT_THAT(this->test_obj_->GetPayloadData16(7),
              xls::status_testing::IsOkAndHolds(0xFE));
}

TEST_F(IrSingleValueQueueTest, ReadPartialDoubleWord) {
  EXPECT_THAT(this->test_obj_->GetPayloadData32(6),
              xls::status_testing::IsOkAndHolds(0));
  XLS_ASSERT_OK(
      this->single_value_queue_->Write(Value(UBits(0xFEDCBA9876543210, 64))));
  EXPECT_THAT(this->test_obj_->GetPayloadData32(6),
              xls::status_testing::IsOkAndHolds(0xFEDC));
  EXPECT_THAT(this->test_obj_->GetPayloadData32(6),
              xls::status_testing::IsOkAndHolds(0xFEDC));
  EXPECT_THAT(this->test_obj_->GetPayloadData32(6),
              xls::status_testing::IsOkAndHolds(0xFEDC));
}

TEST_F(IrSingleValueQueueTest, ReadPartialQuadWord) {
  EXPECT_THAT(this->test_obj_->GetPayloadData64(5),
              xls::status_testing::IsOkAndHolds(0));
  XLS_ASSERT_OK(
      this->single_value_queue_->Write(Value(UBits(0xFEDCBA9876543210, 64))));
  EXPECT_THAT(this->test_obj_->GetPayloadData64(5),
              xls::status_testing::IsOkAndHolds(0xFEDCBA));
  EXPECT_THAT(this->test_obj_->GetPayloadData64(5),
              xls::status_testing::IsOkAndHolds(0xFEDCBA));
  EXPECT_THAT(this->test_obj_->GetPayloadData64(5),
              xls::status_testing::IsOkAndHolds(0xFEDCBA));
}

TEST_F(IrSingleValueQueueTest, WriteByte) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->SetPayloadData8(0, 0x10),
              xls::status_testing::IsOk());
  EXPECT_FALSE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x10, 64))));

  EXPECT_THAT(this->test_obj_->SetPayloadData8(1, 0x10),
              xls::status_testing::IsOk());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x1010, 64))));
}

TEST_F(IrSingleValueQueueTest, WriteWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->SetPayloadData16(0, 0x3210),
              xls::status_testing::IsOk());
  EXPECT_FALSE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x3210, 64))));

  EXPECT_THAT(this->test_obj_->SetPayloadData16(1, 0x3210),
              xls::status_testing::IsOk());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x321010, 64))));
}

TEST_F(IrSingleValueQueueTest, WriteDoubleWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->SetPayloadData32(0, 0x76543210),
              xls::status_testing::IsOk());
  EXPECT_FALSE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x76543210, 64))));

  EXPECT_THAT(this->test_obj_->SetPayloadData32(2, 0x76543210),
              xls::status_testing::IsOk());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x765432103210, 64))));
}

TEST_F(IrSingleValueQueueTest, WriteQuadWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->SetPayloadData64(0, 0xFEDCBA9876543210),
              xls::status_testing::IsOk());
  EXPECT_FALSE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0xFEDCBA9876543210, 64))));
}

TEST_F(IrSingleValueQueueTest, WriteIncorrectOffsetByte) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->SetPayloadData8(16, 0),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, WriteIncorrectOffsetWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->SetPayloadData16(16, 0),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, WriteIncorrectOffsetDoubleWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->SetPayloadData32(16, 0),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, WriteIncorrectOffsetQuadWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(
      this->test_obj_->SetPayloadData64(16, 0),
      xls::status_testing::StatusIs(absl::StatusCode::kInvalidArgument));
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
}

TEST_F(IrSingleValueQueueTest, WritePartialWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->SetPayloadData16(7, 0x3210),
              xls::status_testing::IsOk());
  EXPECT_FALSE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x1000000000000000, 64))));
}

TEST_F(IrSingleValueQueueTest, WritePartialDoubleWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->SetPayloadData32(6, 0x76543210),
              xls::status_testing::IsOk());
  EXPECT_FALSE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x3210000000000000, 64))));
}

TEST_F(IrSingleValueQueueTest, WritePartialQuadWord) {
  EXPECT_TRUE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->test_obj_->SetPayloadData64(5, 0xFEDCBA9876543210),
              xls::status_testing::IsOk());
  EXPECT_FALSE(this->single_value_queue_->IsEmpty());
  EXPECT_THAT(this->single_value_queue_->Read(),
              Optional(Value(UBits(0x5432100000000000, 64))));
}

}  // namespace
}  // namespace xls::simulation::generic
