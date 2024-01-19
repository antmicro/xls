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

#include "xls/simulation/gem5/gem5connection.h"

#include <functional>
#include <memory>
#include <string>
#include <string_view>

#include "absl/strings/str_format.h"
#include "gmock/gmock.h"
#include "gtest/gtest.h"
#include "xls/common/logging/log_flags.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/matchers.h"
#include "xls/simulation/generic/iconnection.h"
#include "xls/simulation/generic/iperipheral_stub.h"
#include "xls/simulation/generic/peripheral_factory.h"

namespace xls::simulation::gem5 {

namespace {

class Gem5Test : public ::testing::Test {
 protected:
  static void SetUpTestSuite() {}
  void SetUp() override {}
};

TEST(Gem5Test, Instantiate) {
  Gem5Connection& instance = Gem5Connection::Instance();
  XLS_LOG(INFO) << absl::StrFormat("Instance: %p", &instance);
}

}  // namespace
}  // namespace xls::simulation::gem5
