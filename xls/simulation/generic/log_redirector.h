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

#ifndef XLS_SIMULATION_GENERIC_LOG_REDIRECTOR_H_
#define XLS_SIMULATION_GENERIC_LOG_REDIRECTOR_H_

#include "absl/log/log_sink.h"
#include "absl/log/log_sink_registry.h"
#include "xls/simulation/generic/iconnection.h"

namespace xls::simulation::generic {

class LogRedirector final : public absl::LogSink {
 public:
  LogRedirector(const LogRedirector&) = delete;
  LogRedirector& operator=(const LogRedirector&) = delete;
  // Log sinks need to have immutable addresses so they can be unregistered
  LogRedirector(LogRedirector&&) = delete;
  LogRedirector& operator=(LogRedirector&&) = delete;

  explicit LogRedirector(IConnection& connection, bool enabled = false);
  ~LogRedirector() override;

  void Enable();
  void Disable();

  void Send(const absl::LogEntry& entry) override;

 protected:
  IConnection& connection_;

 private:
  bool enabled_ = false;
};

}  // namespace xls::simulation::generic

#endif  // XLS_SIMULATION_GENERIC_LOG_REDIRECTOR_H_
