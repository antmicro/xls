// Copyright 2026 The XLS Authors
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

#include "xls/spin/trace_compare.h"

#include <cctype>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/container/flat_hash_set.h"
#include "absl/log/log.h"
#include "absl/status/status.h"
#include "absl/strings/match.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_format.h"
#include "absl/strings/str_split.h"
#include "absl/strings/strip.h"
#include "google/protobuf/text_format.h"
#include "re2/re2.h"
#include "xls/ir/channel.h"
#include "xls/ir/evaluator_result.pb.h"
#include "xls/ir/package.h"
#include "xls/ir/proc.h"
#include "xls/ir/proc_instantiation.h"

namespace xls::spin {

namespace {

// Extracts the DSLX proc class name from an IR proc name.
// Format: __{package}__{ClassName}_{N}_next
// e.g. "__passthrough__Passthrough_0_next" -> "Passthrough"
//      "__channel_naming__MultiplyBy2_0_next" -> "MultiplyBy2"
// Returns "" if the format is not recognised.
std::string ExtractProcClassName(std::string_view ir_name) {
  auto p1 = ir_name.find("__");
  if (p1 == std::string_view::npos) return "";
  auto p2 = ir_name.find("__", p1 + 2);
  if (p2 == std::string_view::npos) return "";
  std::string_view rest = ir_name.substr(p2 + 2);
  if (!absl::EndsWith(rest, "_next")) return "";
  rest.remove_suffix(5);
  auto sep = rest.rfind('_');
  if (sep == std::string_view::npos) return "";
  std::string_view n = rest.substr(sep + 1);
  for (char c : n) {
    if (!std::isdigit(static_cast<unsigned char>(c))) return "";
  }
  return std::string(rest.substr(0, sep));
}

// Recursive helper: walks the instantiation tree from `proc`, building
// ChanNameMap entries keyed by the full DSLX hierarchy path.
// `path` is the current path string (e.g. "PassthroughTest->Passthrough#0").
// `resolved` maps this proc's interface channel names to actual owned channel
// names (transitively from the root proc down).
void WalkInstTree(Proc* proc, std::string_view path,
                  const absl::flat_hash_map<std::string, std::string>& resolved,
                  ChanNameMap& result) {
  absl::flat_hash_map<Proc*, int> inst_count;
  for (const auto& inst : proc->proc_instantiations()) {
    Proc* child = inst->proc();
    int n = inst_count[child]++;
    std::string child_class = ExtractProcClassName(child->name());
    if (child_class.empty()) continue;

    // Resolve child interface params through the parent's resolved map.
    absl::flat_hash_map<std::string, std::string> child_resolved;
    auto iface = child->interface();
    auto args = inst->channel_args();
    for (size_t i = 0; i < std::min(iface.size(), args.size()); ++i) {
      auto it = resolved.find(std::string(args[i]->name()));
      child_resolved[std::string(iface[i]->name())] =
          (it != resolved.end()) ? it->second : std::string(args[i]->name());
    }
    for (Channel* chan : child->channels()) {
      child_resolved[std::string(chan->name())] =
          std::string(inst->name()) + "_" + std::string(chan->name());
    }

    std::string child_path = absl::StrCat(path, "->", child_class, "#", n);

    // Add ChanNameMap entries for this instantiation (interface channels only).
    auto& inner = result[child_path];
    for (ChannelInterface* ci : child->interface()) {
      auto it = child_resolved.find(std::string(ci->name()));
      if (it == child_resolved.end()) continue;
      inner[std::string(absl::StripPrefix(ci->name(), "_"))] =
          std::string(absl::StripPrefix(it->second, "_"));
    }

    WalkInstTree(child, child_path, child_resolved, result);
  }
}

}  // namespace

ChanNameMap BuildChanNameMap(const xls::Package& package) {
  ChanNameMap result;

  // Find root procs (not instantiated by any other proc).
  absl::flat_hash_set<Proc*> is_child;
  for (const auto& proc : package.procs()) {
    for (const auto& inst : proc->proc_instantiations()) {
      is_child.insert(inst->proc());
    }
  }

  for (const auto& proc : package.procs()) {
    if (is_child.contains(proc.get())) continue;
    std::string root_class = ExtractProcClassName(proc->name());
    if (root_class.empty()) continue;

    // Seed resolved map with root proc's owned and interface channels.
    absl::flat_hash_map<std::string, std::string> root_resolved;
    for (Channel* c : proc->channels())
      root_resolved[std::string(c->name())] =
          std::string(proc->name()) + "_" + std::string(c->name());
    for (ChannelInterface* i : proc->interface())
      root_resolved[std::string(i->name())] = std::string(i->name());

    WalkInstTree(proc.get(), root_class, root_resolved, result);
  }
  return result;
}

std::string NormalizeSpinChannel(std::string_view name) {
  return std::string(absl::StripPrefix(name, "_"));
}

std::string NormalizeDslxChannel(std::string_view name,
                                 const ChanNameMap& map) {
  auto pos = name.rfind("::");
  std::string_view local =
      (pos == std::string_view::npos) ? name : name.substr(pos + 2);

  if (!map.empty() && pos != std::string_view::npos) {
    std::string_view path = name.substr(0, pos);
    auto outer = map.find(path);
    if (outer != map.end()) {
      auto inner = outer->second.find(local);
      if (inner != outer->second.end()) return inner->second;
    }
  }

  // Fallback: strip _r/_s direction suffix (for root/test proc events that
  // are never a child proc and so have no entry in the map).
  if (absl::EndsWith(local, "_r") || absl::EndsWith(local, "_s")) {
    local.remove_suffix(2);
  }
  return std::string(local);
}

namespace {

// Decodes a little-endian byte string (from BitsProto.data) to int64_t.
int64_t DecodeBitsLE(const std::string& data) {
  int64_t value = 0;
  for (size_t i = data.size(); i-- > 0;) {
    // char is signed; cast to uint8_t to prevent sign extension into value.
    uint8_t byte_val = static_cast<uint8_t>(data[i]);
    value = (value << 8) | byte_val;
  }
  return value;
}

}  // namespace

absl::Status ParseSpinTrace(std::string_view json, TraceMap& out,
                            std::string_view terminator_channel) {
  const RE2 kRe(
      "\\{\"channel_name\":\"([^\"]*)\","
      "\"direction\":\"([^\"]*)\","
      "\"value\":(-?[0-9]+)\\}");
  for (std::string_view line : absl::StrSplit(json, '\n')) {
    if (line.empty()) continue;
    std::string chan, dir;
    int64_t value = 0;
    if (!RE2::FullMatch(line, kRe, &chan, &dir, &value)) {
      LOG(WARNING) << "SPIN trace: unrecognized line: " << line;
      continue;
    }
    // SPIN's int is 32-bit signed; mask to lower 32 bits to match DSLX's
    // unsigned raw-bits encoding.
    if (value < 0) value &= 0xFFFFFFFFULL;
    std::string norm_chan = NormalizeSpinChannel(chan);
    out[{norm_chan, dir}].push_back(value);
    if (!terminator_channel.empty() && norm_chan == terminator_channel &&
        dir == "SEND") {
      break;
    }
  }
  return absl::OkStatus();
}

absl::Status ParseDslxTrace(std::string_view textproto, TraceMap& out,
                            const ChanNameMap& map,
                            std::string_view terminator_channel) {
  EvaluatorResultsProto proto;
  if (!google::protobuf::TextFormat::ParseFromString(std::string(textproto),
                                                     &proto)) {
    return absl::InvalidArgumentError("DSLX trace text proto parse error");
  }
  bool done = false;
  for (const EvaluatorResultProto& result : proto.results()) {
    if (done) break;
    for (const TraceMessageProto& msg : result.events().trace_msgs()) {
      if (done || !msg.has_channel()) continue;
      const TraceChannelProto& ch = msg.channel();
      std::string direction;
      switch (ch.direction()) {
        case TraceChannelProto::SEND:
          direction = "SEND";
          break;
        case TraceChannelProto::RECV:
          direction = "RECV";
          break;
        default:
          continue;
      }
      int64_t value = 0;
      if (ch.has_value() && ch.value().has_bits()) {
        value = DecodeBitsLE(ch.value().bits().data());
      }
      std::string norm_chan = NormalizeDslxChannel(ch.channel_name(), map);
      out[{norm_chan, direction}].push_back(value);
      if (!terminator_channel.empty() && norm_chan == terminator_channel &&
          direction == "SEND") {
        done = true;
      }
    }
  }
  return absl::OkStatus();
}

absl::Status CompareTraces(const TraceMap& spin, const TraceMap& dslx) {
  std::set<std::pair<std::string, std::string>> all_keys;
  for (const auto& [k, _] : spin) all_keys.insert(k);
  for (const auto& [k, _] : dslx) all_keys.insert(k);

  std::string mismatches;
  for (const auto& key : all_keys) {
    const auto& [chan, dir] = key;
    auto si = spin.find(key);
    auto di = dslx.find(key);
    if (si == spin.end() || di == dslx.end()) continue;
    if (si->second != di->second) {
      absl::StrAppendFormat(
          &mismatches, "  channel=%s dir=%s: spin=%zu dslx=%zu events differ\n",
          chan, dir, si->second.size(), di->second.size());
    }
  }
  if (!mismatches.empty()) {
    return absl::FailedPreconditionError(
        absl::StrFormat("Trace mismatch:\n%s", mismatches));
  }
  return absl::OkStatus();
}

}  // namespace xls::spin
