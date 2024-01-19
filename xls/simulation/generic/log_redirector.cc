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

#include "xls/simulation/generic/log_redirector.h"

#include <memory>
#include <mutex>

#include "absl/log/log.h"
#include "absl/log/log_entry.h"
#include "absl/log/log_sink_registry.h"
#include "log_redirector.h"
#include "xls/common/logging/log_flags.h"
#include "xls/common/logging/logging.h"

namespace xls::simulation::generic {

static std::mutex LogRegistrationMutex;
static struct {
  size_t redirectors_count = 0;
  int restore_stderrthreshold = 0;
} LogRedirectorGlobals;

LogRedirector::LogRedirector(IConnection& connection, bool enabled)
    : connection_(connection) {
  if (enabled) {
    Enable();
  }
}

LogRedirector::~LogRedirector() { Disable(); }

void LogRedirector::Enable() {
  if (enabled_) return;

  LogRegistrationMutex.lock();

  bool do_store = LogRedirectorGlobals.redirectors_count++ == 0;

  if (do_store) {
    // absl::GetFlag is internal. We can't store the original flags, so let's
    // assume some values.
    LogRedirectorGlobals.restore_stderrthreshold =
        static_cast<int>(absl::LogSeverityAtLeast::kWarning);
  }

  absl::SetFlag(&FLAGS_logtostderr, true);
  absl::AddLogSink(this);
  absl::SetFlag(&FLAGS_logtostderr, false);

  if (do_store) {
    absl::SetFlag(&FLAGS_stderrthreshold,
                  static_cast<int>(absl::LogSeverityAtLeast::kInfinity));
  }

  enabled_ = true;

  LogRegistrationMutex.unlock();
}

void LogRedirector::Disable() {
  if (!enabled_) return;

  LogRegistrationMutex.lock();

  absl::SetFlag(&FLAGS_logtostderr, false);
  absl::RemoveLogSink(this);
  absl::SetFlag(&FLAGS_logtostderr, true);

  if (--LogRedirectorGlobals.redirectors_count == 0) {
    absl::SetFlag(&FLAGS_stderrthreshold,
                  LogRedirectorGlobals.restore_stderrthreshold);
  }

  LogRegistrationMutex.unlock();
}

void LogRedirector::Send(const absl::LogEntry& entry) {
  XLS_CHECK_OK(connection_.Log(entry.log_severity(), entry.text_message()));
}

}  // namespace xls::simulation::generic
