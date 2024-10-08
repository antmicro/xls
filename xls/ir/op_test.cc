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

#include "xls/ir/op.h"

#include "gtest/gtest.h"

namespace xls {
namespace {

class IrOpTest : public testing::TestWithParam<Op> {};

TEST_P(IrOpTest, NoDuplicateProtoValues) {
  for (Op other_op : kAllOps) {
    if (other_op != GetParam()) {
      EXPECT_NE(ToOpProto(GetParam()), ToOpProto(other_op)) << other_op;
    }
  }
}

TEST_P(IrOpTest, NoDuplicateStringValues) {
  for (Op other_op : kAllOps) {
    if (other_op != GetParam()) {
      EXPECT_NE(OpToString(GetParam()), OpToString(other_op)) << other_op;
    }
  }
}

INSTANTIATE_TEST_SUITE_P(IrOpTest, IrOpTest, testing::ValuesIn(kAllOps),
                         testing::PrintToStringParamName());
}  // namespace
}  // namespace xls
