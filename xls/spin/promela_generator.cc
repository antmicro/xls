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

#include "xls/spin/promela_generator.h"

#include <cctype>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/container/flat_hash_set.h"
#include "absl/log/log.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/match.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_replace.h"
#include "absl/strings/str_format.h"
#include "absl/strings/str_join.h"
#include "absl/strings/substitute.h"
#include "xls/common/status/status_macros.h"
#include "xls/ir/channel.h"
#include "xls/ir/dfs_visitor.h"
#include "xls/ir/function.h"
#include "xls/ir/function_base.h"
#include "xls/ir/node.h"
#include "xls/ir/nodes.h"
#include "xls/ir/op.h"
#include "xls/ir/package.h"
#include "xls/ir/proc.h"
#include "xls/ir/proc_instantiation.h"
#include "xls/ir/source_location.h"
#include "xls/ir/state_element.h"
#include "xls/ir/type.h"
#include "xls/ir/value.h"

namespace xls {
namespace spin {
namespace {

bool IsUnitType(Type* type) {
  return type->IsTuple() && type->AsTupleOrDie()->size() == 0;
}

std::string PromelaType(Type* type) {
  if (type->IsToken() || IsUnitType(type)) return "";
  if (type->IsBits()) {
    const int64_t bits = type->AsBitsOrDie()->bit_count();
    if (bits == 1) return "bit";
    if (bits <= 8) return "byte";
    if (bits <= 16) return "short";
    return "int";
  }
  LOG(WARNING) << "Type '" << type->ToString()
               << "' has no Promela equivalent; approximated as int (lossy).";
  return "int";
}

std::string SanitizeName(std::string_view name) {
  std::string result;
  result.reserve(name.size());
  for (char c : name) {
    unsigned char uc = static_cast<unsigned char>(c);
    result.push_back((std::isalnum(uc) || c == '_') ? c : '_');
  }
  if (!result.empty() && std::isdigit(static_cast<unsigned char>(result[0])))
    result.insert(result.begin(), '_');
  return result;
}

std::string BitsLiteralStr(const Value& value) {
  if (!value.IsBits()) return "0";
  auto uint_val = value.bits().ToUint64();
  return uint_val.ok() ? absl::StrCat(*uint_val) : "0 /* oversized */";
}

bool HasBodyOps(Proc* proc) {
  for (Node* n : proc->nodes()) {
    if (n->op() == Op::kReceive || n->op() == Op::kSend ||
        n->op() == Op::kAssert)
      return true;
  }
  for (StateElement* se : proc->StateElements()) {
    if (!se->type()->IsToken() && !IsUnitType(se->type())) return true;
  }
  return false;
}

std::vector<std::string> ProcParams(Proc* proc) {
  std::vector<std::string> params;
  absl::flat_hash_set<std::string> seen;
  for (ChannelInterface* iface : proc->interface()) {
    if (seen.emplace(iface->name()).second)
      params.push_back(std::string(iface->name()));
  }
  return params;
}

}  // namespace

// ---------------------------------------------------------------------------
// Constructor / factory
// ---------------------------------------------------------------------------

PromelaGenerator::PromelaGenerator(Package* package,
                                   const PromelaGeneratorOptions& options)
    : package_(package), options_(options), emit_(out_) {}

absl::StatusOr<std::string> PromelaGenerator::Generate(
    Package* package, const PromelaGeneratorOptions& options) {
  PromelaGenerator gen(package, options);

  if (!package->procs().empty() && !package->ChannelsAreProcScoped()) {
    return absl::InvalidArgumentError(
        absl::StrCat("Package '", package->name(),
                     "' has procs with old-style (package-level) channels. "
                     "Re-generate the IR with proc-scoped channels enabled "
                     "(lower_to_proc_scoped_channels pass)."));
  }

  XLS_RETURN_IF_ERROR(gen.ValidateTypes());

  gen.emit_.Line("/* Promela model generated from XLS IR package: $0 */",
                 package->name());
  gen.emit_.Blank();

  if (options.emit_termination_hook) {
    gen.emit_.Line("bit __terminated = 0;");
    gen.emit_.Blank();
  }

  for (const auto& fn : package->functions())
    XLS_RETURN_IF_ERROR(gen.EmitFunction(fn.get()));

  for (const auto& proc : package->procs()) {
    if (!proc->is_new_style_proc()) continue;
    if (!HasBodyOps(proc.get()) && proc->channels().empty() &&
        proc->proc_instantiations().empty())
      continue;
    XLS_RETURN_IF_ERROR(gen.EmitProc(proc.get()));
  }

  std::vector<Proc*> roots = gen.FindRootProcs();
  if (!roots.empty()) gen.EmitInit(roots);

  return gen.out_;
}

// ---------------------------------------------------------------------------
// Package-level orchestration
// ---------------------------------------------------------------------------

// Rejects any node or channel type wider than 32 bits (Promela int limit).
absl::Status PromelaGenerator::ValidateTypes() {
  auto check = [](Type* type, std::string_view ctx) -> absl::Status {
    if (type->IsBits() && type->AsBitsOrDie()->bit_count() > 32) {
      return absl::InvalidArgumentError(
          absl::StrCat(ctx, " has bit width ", type->AsBitsOrDie()->bit_count(),
                       " which exceeds Promela's maximum of 32 (int)."));
    }
    return absl::OkStatus();
  };
  for (const auto& fn : package_->functions())
    for (Node* n : fn->nodes())
      XLS_RETURN_IF_ERROR(check(
          n->GetType(), absl::StrCat("node '", n->GetName(), "' in function '",
                                     fn->name(), "'")));
  for (const auto& proc : package_->procs()) {
    for (Node* n : proc->nodes())
      XLS_RETURN_IF_ERROR(
          check(n->GetType(), absl::StrCat("node '", n->GetName(),
                                           "' in proc '", proc->name(), "'")));
    for (ChannelInterface* i : proc->interface())
      XLS_RETURN_IF_ERROR(
          check(i->type(), absl::StrCat("channel '", i->name(), "' in proc '",
                                        proc->name(), "'")));
    for (Channel* c : proc->channels())
      XLS_RETURN_IF_ERROR(
          check(c->type(), absl::StrCat("channel '", c->name(), "' in proc '",
                                        proc->name(), "'")));
  }
  return absl::OkStatus();
}

// Returns procs that are not instantiated by any other proc (top-level roots).
std::vector<Proc*> PromelaGenerator::FindRootProcs() const {
  absl::flat_hash_set<Proc*> is_child;
  for (const auto& proc : package_->procs())
    for (const auto& inst : proc->proc_instantiations())
      is_child.insert(inst->proc());
  std::vector<Proc*> roots;
  for (const auto& proc : package_->procs())
    if (proc->is_new_style_proc() && !is_child.contains(proc.get()))
      roots.push_back(proc.get());
  return roots;
}

// Emits a Promela inline macro for `fn`; result is passed via an out-parameter.
absl::Status PromelaGenerator::EmitFunction(Function* fn) {
  std::vector<std::string> param_parts;
  for (Param* p : fn->params()) param_parts.push_back(SanitizeName(p->name()));
  param_parts.push_back("_ret");

  emit_.Line("inline fn_$0($1) {", SanitizeName(fn->name()),
             absl::StrJoin(param_parts, ", "));
  emit_.Indent();

  next_nodes_.clear();
  tuple_components_.clear();
  XLS_RETURN_IF_ERROR(fn->Accept(this));

  std::string_view ret_var = Ref(fn->return_value());
  if (!ret_var.empty()) emit_.Line("_ret = $0;", ret_var);
  emit_.Dedent();
  emit_.Line("}");
  emit_.Blank();
  return absl::OkStatus();
}

// Emits a Promela proctype for `proc`, including channel decls, child spawns,
// xr/xs hints, state variables, and the do/od main loop.
absl::Status PromelaGenerator::EmitProc(Proc* proc) {
  absl::flat_hash_set<std::string> send_chans, recv_chans;
  for (Node* n : proc->nodes()) {
    if (n->op() == Op::kSend)
      send_chans.insert(std::string(n->As<Send>()->channel_name()));
    else if (n->op() == Op::kReceive)
      recv_chans.insert(std::string(n->As<Receive>()->channel_name()));
  }

  std::vector<std::string> param_parts;
  for (const std::string& p : ProcParams(proc))
    param_parts.push_back(absl::StrCat("chan ", SanitizeName(p)));
  emit_.Line("proctype $0($1) {", SanitizeName(proc->name()),
             absl::StrJoin(param_parts, "; "));
  emit_.Indent();

  for (Channel* chan : proc->channels()) {
    std::string elem_type = PromelaType(chan->type());
    if (elem_type.empty()) elem_type = "bit";
    emit_.Line("chan $0 = [$1] of { $2 };", SanitizeName(chan->name()),
               options_.channel_depth, elem_type);
  }
  if (!proc->channels().empty()) emit_.Blank();

  for (const auto& inst : proc->proc_instantiations()) {
    std::vector<std::string> args;
    for (ChannelInterface* a : inst->channel_args())
      args.push_back(SanitizeName(a->name()));
    emit_.Line("run $0($1);", SanitizeName(inst->proc()->name()),
               absl::StrJoin(args, ", "));
  }
  if (!proc->proc_instantiations().empty()) emit_.Blank();

  for (const std::string& chan : recv_chans)
    emit_.Line("xr $0;", SanitizeName(chan));
  for (const std::string& chan : send_chans)
    emit_.Line("xs $0;", SanitizeName(chan));
  if (!recv_chans.empty() || !send_chans.empty()) emit_.Blank();

  if (!HasBodyOps(proc)) {
    emit_.Dedent();
    emit_.Line("}");
    emit_.Blank();
    return absl::OkStatus();
  }

  for (StateElement* se : proc->StateElements()) {
    const std::string stype = PromelaType(se->type());
    if (stype.empty()) continue;
    emit_.Line("$0 s_$1 = $2;", stype, SanitizeName(se->name()),
               BitsLiteralStr(se->initial_value()));
  }

  const std::string proc_key = SanitizeName(proc->name());
  auto thr_it = options_.worst_case_throughput.find(proc_key);
  const int throughput =
      (thr_it != options_.worst_case_throughput.end()) ? thr_it->second : 1;
  const bool use_thr = throughput > 1;

  if (use_thr)
    emit_.Line("$0 __thr = 0;", (throughput <= 256) ? "byte" : "short");
  if (proc->GetStateElementCount() > 0 || use_thr) emit_.Blank();

  emit_.Line("do");
  if (options_.emit_termination_hook) emit_.Line(":: (__terminated) -> break");
  if (use_thr) {
    emit_.Line(":: (__thr > 0) -> __thr--;");
    emit_.Line(":: (__thr == 0) ->");
    emit_.Line("__thr = $0;", throughput - 1);
  } else {
    emit_.Line("::");
  }

  next_nodes_.clear();
  tuple_components_.clear();
  XLS_RETURN_IF_ERROR(proc->Accept(this));

  for (Node* n : next_nodes_) {
    auto* nx = n->As<Next>();
    if (nx->state_element()->type()->IsToken() ||
        IsUnitType(nx->state_element()->type()))
      continue;
    const std::string svar =
        absl::StrCat("s_", SanitizeName(nx->state_element()->name()));
    std::string_view val = Ref(nx->value());
    if (val.empty()) val = "0";
    if (nx->predicate().has_value()) {
      std::string_view pred = Ref(*nx->predicate());
      if (pred.empty()) pred = "0";
      emit_.Line("if");
      emit_.Line(":: ($0 != 0) -> $1 = $2;", pred, svar, val);
      emit_.Line(":: else -> skip;");
      emit_.Line("fi");
    } else {
      emit_.Line("$0 = $1;", svar, val);
    }
  }

  emit_.Line("od");
  emit_.Dedent();
  emit_.Line("}");
  emit_.Blank();
  return absl::OkStatus();
}

// Emits the Promela init block: declares interface channels and spawns roots.
void PromelaGenerator::EmitInit(const std::vector<Proc*>& root_procs) {
  emit_.Line("init {");
  emit_.Indent();

  std::map<std::string, Type*> iface_chans;
  for (Proc* rp : root_procs)
    for (ChannelInterface* i : rp->interface())
      iface_chans.emplace(SanitizeName(i->name()), i->type());
  for (const auto& [name, type] : iface_chans) {
    std::string elem_type = PromelaType(type);
    if (elem_type.empty()) elem_type = "bit";
    emit_.Line("chan $0 = [$1] of { $2 };", name, options_.channel_depth,
               elem_type);
  }
  if (!iface_chans.empty()) emit_.Blank();

  for (Proc* rp : root_procs) {
    std::vector<std::string> args;
    for (const std::string& p : ProcParams(rp)) args.push_back(SanitizeName(p));
    emit_.Line("run $0($1);", SanitizeName(rp->name()),
               absl::StrJoin(args, ", "));
  }

  if (options_.emit_termination_hook) {
    for (const auto& [name, unused] : iface_chans) {
      if (absl::StrContains(name, "terminator")) {
        emit_.Line("bit __term_val;");
        emit_.Line("$0 ? __term_val;", name);
        emit_.Line("__terminated = 1;");
        break;
      }
    }
  }

  emit_.Dedent();
  emit_.Line("}");
}

// ---------------------------------------------------------------------------
// Node name tracking
// ---------------------------------------------------------------------------

// Associates `name` with `node` for later Ref() lookup.
absl::Status PromelaGenerator::SetName(Node* node, std::string name) {
  if (node != nullptr) names_[node] = std::move(name);
  return absl::OkStatus();
}

// Returns the Promela variable name recorded for `node`, or "" if none.
std::string_view PromelaGenerator::Ref(Node* node) const {
  auto it = names_.find(node);
  return (it != names_.end()) ? std::string_view(it->second) : "";
}

// Returns the canonical Promela variable name for `node` (v_<sanitized_name>).
std::string PromelaGenerator::Var(Node* node) const {
  return absl::StrCat("v_", SanitizeName(node->GetName()));
}

// ---------------------------------------------------------------------------
// Code emission helpers
// ---------------------------------------------------------------------------

// Declares a typed Promela variable initialised to `expr`; masks narrow ints.
absl::Status PromelaGenerator::Assign(Node* node, std::string_view expr) {
  MaybeEmitLocComment(node);
  MaybeEmitIrHintComment(node);
  const std::string var = Var(node);
  if (node->GetType()->IsBits()) {
    const int64_t n = node->GetType()->AsBitsOrDie()->bit_count();
    if (n > 1 && n < 32) {
      const uint64_t mask = (uint64_t{1} << n) - 1;
      Emit("int $0 = ($1) & $2;", var, expr, mask);
      return SetName(node, var);
    }
  }
  Emit("$0 $1 = $2;", PromelaType(node->GetType()), var, expr);
  return SetName(node, var);
}

// Emits an if/fi block that sets a bit variable to 1 if `lhs cmp_op rhs`.
absl::Status PromelaGenerator::EmitCompare(CompareOp* node,
                                           std::string_view cmp_op) {
  MaybeEmitLocComment(node);
  MaybeEmitIrHintComment(node);
  const std::string var = Var(node);
  Emit("bit $0;", var);
  Emit("if");
  Emit(":: ($0 $1 $2) -> $3 = 1;", Ref(node->operand(0)), cmp_op,
       Ref(node->operand(1)), var);
  Emit(":: else -> $0 = 0;", var);
  Emit("fi");
  return SetName(node, var);
}

// Emits an n-ary bitwise expression joined by `op_sym`, optionally inverted.
absl::Status PromelaGenerator::EmitNaryBitwise(NaryOp* node,
                                               std::string_view op_sym,
                                               bool invert) {
  std::vector<std::string> parts;
  parts.reserve(node->operand_count());
  for (int64_t i = 0; i < node->operand_count(); ++i)
    parts.emplace_back(Ref(node->operand(i)));
  const std::string expr = absl::StrJoin(parts, absl::StrCat(" ", op_sym, " "));
  if (invert) {
    bool is_bit = node->GetType()->IsBits() &&
                  node->GetType()->AsBitsOrDie()->bit_count() == 1;
    return Assign(node, absl::StrCat(is_bit ? "!" : "~", "(", expr, ")"));
  }
  return Assign(node, expr);
}

// Emits an if/fi that sets a bit to 1 when `operand cmp_op sentinel`.
absl::Status PromelaGenerator::EmitBitwiseReduce(BitwiseReductionOp* node,
                                                 std::string_view cmp_op,
                                                 std::string_view sentinel) {
  MaybeEmitLocComment(node);
  MaybeEmitIrHintComment(node);
  const std::string var = Var(node);
  Emit("bit $0;", var);
  Emit("if");
  Emit(":: ($0 $1 $2) -> $3 = 1;", Ref(node->operand(0)), cmp_op, sentinel,
       var);
  Emit(":: else -> $0 = 0;", var);
  Emit("fi");
  return SetName(node, var);
}

// Emits a multiply; shared by HandleUMul and HandleSMul.
absl::Status PromelaGenerator::EmitMul(ArithOp* mul) {
  return Assign(
      mul, absl::StrCat(Ref(mul->operand(0)), " * ", Ref(mul->operand(1))));
}

// Returns "progress_<dir>_<chan>: " when emit_progress_labels is set, else "".
std::string PromelaGenerator::ProgressLabel(std::string_view dir,
                                            std::string_view chan) const {
  if (!options_.emit_progress_labels) return "";
  return absl::StrCat("progress_", dir, "_", chan, ": ");
}

// Emits /* file:line:col */ when emit_source_locations is set and node has loc.
void PromelaGenerator::MaybeEmitLocComment(Node* node) {
  if (!options_.emit_source_locations) return;
  const SourceInfo& info = node->loc();
  if (info.Empty()) return;
  const SourceLocation& loc = info.locations.front();
  std::optional<std::string> filename = package_->GetFilename(loc.fileno());
  const std::string file_part =
      filename.has_value() ? *filename
                           : absl::StrCat("file:", loc.fileno().value());
  Emit("/* $0:$1:$2 */", file_part, loc.lineno().value(), loc.colno().value());
}

// Emits /* ir: <node-expr> */ when emit_source_hints is set.
void PromelaGenerator::MaybeEmitIrHintComment(Node* node) {
  if (!options_.emit_source_hints) return;
  std::string repr = node->ToString();
  for (char& c : repr)
    if (c == '\n' || c == '\r') c = ' ';
  Emit("/* ir: $0 */", repr);
}

// ---------------------------------------------------------------------------
// DfsVisitorWithDefault overrides
// ---------------------------------------------------------------------------

absl::Status PromelaGenerator::DefaultHandler(Node* node) {
  if (node->GetType()->IsToken() || IsUnitType(node->GetType()))
    return SetName(node, "");
  return absl::UnimplementedError(
      absl::StrCat("unsupported op: ", OpToString(node->op())));
}

absl::Status PromelaGenerator::HandleAfterAll(AfterAll* n) {
  return SetName(n, "");
}
absl::Status PromelaGenerator::HandleMinDelay(MinDelay* n) {
  return SetName(n, "");
}
absl::Status PromelaGenerator::HandleTrace(Trace* n) { return SetName(n, ""); }
absl::Status PromelaGenerator::HandleCover(Cover* n) { return SetName(n, ""); }
absl::Status PromelaGenerator::HandleNewChannel(NewChannel* n) {
  return SetName(n, "");
}
absl::Status PromelaGenerator::HandleRecvChannelEnd(RecvChannelEnd* n) {
  return SetName(n, "");
}
absl::Status PromelaGenerator::HandleSendChannelEnd(SendChannelEnd* n) {
  return SetName(n, "");
}
absl::Status PromelaGenerator::HandleParam(Param* param) {
  return SetName(param, SanitizeName(param->name()));
}

absl::Status PromelaGenerator::HandleStateRead(StateRead* sr) {
  if (sr->GetType()->IsToken() || IsUnitType(sr->GetType()))
    return SetName(sr, "");
  return SetName(sr,
                 absl::StrCat("s_", SanitizeName(sr->state_element()->name())));
}

absl::Status PromelaGenerator::HandleNext(Next* next) {
  next_nodes_.push_back(next);
  return SetName(next, "");
}

absl::Status PromelaGenerator::HandleLiteral(Literal* lit) {
  if (lit->GetType()->IsToken() || IsUnitType(lit->GetType()))
    return SetName(lit, "");
  return Assign(lit,
                lit->value().IsBits() ? BitsLiteralStr(lit->value()) : "0");
}

absl::Status PromelaGenerator::HandleAdd(BinOp* add) {
  return Assign(
      add, absl::StrCat(Ref(add->operand(0)), " + ", Ref(add->operand(1))));
}
absl::Status PromelaGenerator::HandleSub(BinOp* sub) {
  return Assign(
      sub, absl::StrCat(Ref(sub->operand(0)), " - ", Ref(sub->operand(1))));
}
absl::Status PromelaGenerator::HandleUMul(ArithOp* mul) { return EmitMul(mul); }
absl::Status PromelaGenerator::HandleSMul(ArithOp* mul) { return EmitMul(mul); }
absl::Status PromelaGenerator::HandleUDiv(BinOp* div) {
  return Assign(
      div, absl::StrCat(Ref(div->operand(0)), " / ", Ref(div->operand(1))));
}
absl::Status PromelaGenerator::HandleSDiv(BinOp* div) {
  return Assign(
      div, absl::StrCat(Ref(div->operand(0)), " / ", Ref(div->operand(1))));
}
absl::Status PromelaGenerator::HandleUMod(BinOp* mod) {
  return Assign(
      mod, absl::StrCat(Ref(mod->operand(0)), " % ", Ref(mod->operand(1))));
}
absl::Status PromelaGenerator::HandleSMod(BinOp* mod) {
  return Assign(
      mod, absl::StrCat(Ref(mod->operand(0)), " % ", Ref(mod->operand(1))));
}
absl::Status PromelaGenerator::HandleNeg(UnOp* neg) {
  return Assign(neg, absl::StrCat("-", Ref(neg->operand(0))));
}
absl::Status PromelaGenerator::HandleIdentity(UnOp* id) {
  return Assign(id, Ref(id->operand(0)));
}

absl::Status PromelaGenerator::HandleNot(UnOp* not_op) {
  if (!not_op->GetType()->IsBits()) return DefaultHandler(not_op);
  const int64_t n = not_op->GetType()->AsBitsOrDie()->bit_count();
  std::string_view arg = Ref(not_op->operand(0));
  if (n == 1) return Assign(not_op, absl::StrCat("!(", arg, ")"));
  return Assign(not_op, absl::StrCat("~(", arg, ")"));
}

absl::Status PromelaGenerator::HandleNaryAnd(NaryOp* n) {
  return EmitNaryBitwise(n, "&");
}
absl::Status PromelaGenerator::HandleNaryOr(NaryOp* n) {
  return EmitNaryBitwise(n, "|");
}
absl::Status PromelaGenerator::HandleNaryXor(NaryOp* n) {
  return EmitNaryBitwise(n, "^");
}
absl::Status PromelaGenerator::HandleNaryNand(NaryOp* n) {
  return EmitNaryBitwise(n, "&", /*invert=*/true);
}
absl::Status PromelaGenerator::HandleNaryNor(NaryOp* n) {
  return EmitNaryBitwise(n, "|", /*invert=*/true);
}

absl::Status PromelaGenerator::HandleAndReduce(BitwiseReductionOp* n) {
  const int64_t src_bits = n->operand(0)->GetType()->AsBitsOrDie()->bit_count();
  const std::string sentinel =
      (src_bits >= 32) ? "-1" : absl::StrCat((uint64_t{1} << src_bits) - 1);
  return EmitBitwiseReduce(n, "==", sentinel);
}
absl::Status PromelaGenerator::HandleOrReduce(BitwiseReductionOp* n) {
  return EmitBitwiseReduce(n, "!=", "0");
}
absl::Status PromelaGenerator::HandleShll(BinOp* n) {
  return Assign(n, absl::StrCat("(", Ref(n->operand(0)), " << ",
                                Ref(n->operand(1)), ")"));
}
absl::Status PromelaGenerator::HandleShrl(BinOp* n) {
  return Assign(n, absl::StrCat("(", Ref(n->operand(0)), " >> ",
                                Ref(n->operand(1)), ")"));
}
absl::Status PromelaGenerator::HandleShra(BinOp* n) {
  return Assign(n, absl::StrCat("(", Ref(n->operand(0)), " >> ",
                                Ref(n->operand(1)), ")"));
}

absl::Status PromelaGenerator::HandleEq(CompareOp* n) {
  return EmitCompare(n, "==");
}
absl::Status PromelaGenerator::HandleNe(CompareOp* n) {
  return EmitCompare(n, "!=");
}
absl::Status PromelaGenerator::HandleULt(CompareOp* n) {
  return EmitCompare(n, "<");
}
absl::Status PromelaGenerator::HandleULe(CompareOp* n) {
  return EmitCompare(n, "<=");
}
absl::Status PromelaGenerator::HandleUGt(CompareOp* n) {
  return EmitCompare(n, ">");
}
absl::Status PromelaGenerator::HandleUGe(CompareOp* n) {
  return EmitCompare(n, ">=");
}
absl::Status PromelaGenerator::HandleSLt(CompareOp* n) {
  return EmitCompare(n, "<");
}
absl::Status PromelaGenerator::HandleSLe(CompareOp* n) {
  return EmitCompare(n, "<=");
}
absl::Status PromelaGenerator::HandleSGt(CompareOp* n) {
  return EmitCompare(n, ">");
}
absl::Status PromelaGenerator::HandleSGe(CompareOp* n) {
  return EmitCompare(n, ">=");
}

absl::Status PromelaGenerator::HandleBitSlice(BitSlice* bs) {
  const int64_t w = bs->width();
  const uint64_t mask = (w >= 64) ? ~uint64_t{0} : ((uint64_t{1} << w) - 1);
  return Assign(bs, absl::StrFormat("(%s >> %d) & %u", Ref(bs->operand(0)),
                                    bs->start(), mask));
}

absl::Status PromelaGenerator::HandleDynamicBitSlice(DynamicBitSlice* dbs) {
  const int64_t w = dbs->width();
  const uint64_t mask = (w >= 64) ? ~uint64_t{0} : ((uint64_t{1} << w) - 1);
  return Assign(dbs, absl::StrFormat("(%s >> %s) & %u", Ref(dbs->operand(0)),
                                     Ref(dbs->operand(1)), mask));
}

absl::Status PromelaGenerator::HandleSignExtend(ExtendOp* ext) {
  MaybeEmitLocComment(ext);
  MaybeEmitIrHintComment(ext);
  const int64_t src_bits =
      ext->operand(0)->GetType()->AsBitsOrDie()->bit_count();
  const uint64_t sign_bit = uint64_t{1} << (src_bits - 1);
  const uint64_t low_mask = sign_bit - 1;
  std::string_view arg = Ref(ext->operand(0));
  const std::string var = Var(ext);
  Emit("int $0;", var);
  Emit("if");
  Emit(":: (($0 & $1) != 0) -> $2 = $0 | (~$3);", arg, sign_bit, var, low_mask);
  Emit(":: else -> $0 = $1;", var, arg);
  Emit("fi");
  return SetName(ext, var);
}

absl::Status PromelaGenerator::HandleZeroExtend(ExtendOp* ext) {
  return Assign(ext, Ref(ext->operand(0)));
}

absl::Status PromelaGenerator::HandleConcat(Concat* concat) {
  const std::string var = Var(concat);
  Emit("$0 $1 = 0;", PromelaType(concat->GetType()), var);
  int64_t shift = 0;
  for (int64_t i = concat->operand_count() - 1; i >= 0; --i) {
    Node* op = concat->operand(i);
    const int64_t w =
        op->GetType()->IsBits() ? op->GetType()->AsBitsOrDie()->bit_count() : 8;
    const uint64_t mask = (w >= 64) ? ~uint64_t{0} : ((uint64_t{1} << w) - 1);
    if (shift == 0)
      Emit("$0 = $0 | ($1 & $2);", var, Ref(op), mask);
    else
      Emit("$0 = $0 | (($1 & $2) << $3);", var, Ref(op), mask, shift);
    shift += w;
  }
  return SetName(concat, var);
}

absl::Status PromelaGenerator::HandleSel(Select* sel) {
  MaybeEmitLocComment(sel);
  MaybeEmitIrHintComment(sel);
  const std::string var = Var(sel);
  Emit("$0 $1;", PromelaType(sel->GetType()), var);
  Emit("if");
  for (size_t i = 0; i < sel->cases().size(); ++i)
    Emit(":: ($0 == $1) -> $2 = $3;", Ref(sel->selector()), i, var,
         Ref(sel->get_case(i)));
  if (sel->default_value().has_value())
    Emit(":: else -> $0 = $1;", var, Ref(*sel->default_value()));
  else if (!sel->cases().empty())
    Emit(":: else -> $0 = $1;", var,
         Ref(sel->get_case(sel->cases().size() - 1)));
  Emit("fi");
  return SetName(sel, var);
}

absl::Status PromelaGenerator::HandleOneHotSel(OneHotSelect* ohs) {
  const std::string var = Var(ohs);
  Emit("$0 $1 = 0;", PromelaType(ohs->GetType()), var);
  for (size_t i = 0; i < ohs->cases().size(); ++i) {
    Emit("if");
    Emit(":: ((($0 >> $1) & 1) == 1) -> $2 = $2 | $3;", Ref(ohs->selector()), i,
         var, Ref(ohs->get_case(i)));
    Emit(":: else -> skip;");
    Emit("fi");
  }
  return SetName(ohs, var);
}

absl::Status PromelaGenerator::HandlePrioritySel(PrioritySelect* ps) {
  const std::string var = Var(ps);
  Emit("$0 $1 = $2;", PromelaType(ps->GetType()), var,
       Ref(ps->default_value()));
  for (int64_t i = ps->cases().size() - 1; i >= 0; --i) {
    Emit("if");
    Emit(":: ((($0 >> $1) & 1) == 1) -> $2 = $3;", Ref(ps->selector()), i, var,
         Ref(ps->get_case(i)));
    Emit(":: else -> skip;");
    Emit("fi");
  }
  return SetName(ps, var);
}

absl::Status PromelaGenerator::HandleGate(Gate* gate) {
  MaybeEmitLocComment(gate);
  MaybeEmitIrHintComment(gate);
  const std::string var = Var(gate);
  Emit("$0 $1;", PromelaType(gate->GetType()), var);
  Emit("if");
  Emit(":: ($0 != 0) -> $1 = $2;", Ref(gate->condition()), var,
       Ref(gate->data()));
  Emit(":: else -> $0 = 0;", var);
  Emit("fi");
  return SetName(gate, var);
}

absl::Status PromelaGenerator::HandleTuple(Tuple* tuple) {
  if (IsUnitType(tuple->GetType())) return SetName(tuple, "");
  std::vector<std::string> comps;
  comps.reserve(tuple->operand_count());
  for (Node* op : tuple->operands()) comps.emplace_back(Ref(op));
  tuple_components_[tuple] = std::move(comps);
  return SetName(tuple, "");
}

absl::Status PromelaGenerator::HandleTupleIndex(TupleIndex* ti) {
  if (ti->GetType()->IsToken() || IsUnitType(ti->GetType()))
    return SetName(ti, "");
  Node* src = ti->operand(0);
  if (src->op() == Op::kReceive) {
    if (ti->index() == 1) return SetName(ti, std::string(Ref(src)));
    if (ti->index() == 2 && !src->As<Receive>()->is_blocking())
      return SetName(ti, absl::StrCat(Ref(src), "_valid"));
    return SetName(ti, "");
  }
  auto it = tuple_components_.find(src);
  if (it != tuple_components_.end()) {
    const auto& comps = it->second;
    if (static_cast<size_t>(ti->index()) < comps.size())
      return SetName(ti, comps[ti->index()]);
    return SetName(ti, "");
  }
  return Assign(
      ti, absl::StrCat(Ref(src), " /* tuple_index[", ti->index(), "] */"));
}

absl::Status PromelaGenerator::HandleReceive(Receive* recv) {
  MaybeEmitLocComment(recv);
  MaybeEmitIrHintComment(recv);
  Type* payload = recv->GetPayloadType();
  const std::string ptype = PromelaType(payload);
  const std::string chan = SanitizeName(recv->channel_name());
  const std::string prog_recv = ProgressLabel("recv", chan);

  if (ptype.empty()) {
    if (recv->predicate().has_value()) {
      Emit("if");
      Emit(":: ($0 != 0) -> $1$2 ? eval(0);", Ref(*recv->predicate()),
           prog_recv, chan);
      Emit(":: else -> skip;");
      Emit("fi");
    } else {
      Emit("$0$1 ? eval(0);", prog_recv, chan);
    }
    return SetName(recv, "");
  }

  const std::string data_var = absl::StrCat(Var(recv), "_data");
  Emit("$0 $1;", ptype, data_var);

  if (!recv->is_blocking()) {
    const std::string valid_var = data_var + "_valid";
    Emit("bit $0;", valid_var);
    Emit("atomic {");
    Emit("if");
    if (recv->predicate().has_value()) {
      std::string_view pred = Ref(*recv->predicate());
      Emit(":: ($0 != 0) && $1?[$2] -> $3$1 ? $2; $4 = 1;", pred, chan,
           data_var, prog_recv, valid_var);
    } else {
      Emit(":: $0?[$1] -> $2$0 ? $1; $3 = 1;", chan, data_var, prog_recv,
           valid_var);
    }
    Emit(":: else -> $0 = 0;", valid_var);
    Emit("fi");
    Emit("}");
    return SetName(recv, data_var);
  }

  if (recv->predicate().has_value()) {
    Emit("if");
    Emit(":: ($0 != 0) -> $1$2 ? $3;", Ref(*recv->predicate()), prog_recv, chan,
         data_var);
    Emit(":: else -> skip;");
    Emit("fi");
  } else {
    Emit("$0$1 ? $2;", prog_recv, chan, data_var);
  }
  return SetName(recv, data_var);
}

absl::Status PromelaGenerator::HandleSend(Send* snd) {
  MaybeEmitLocComment(snd);
  MaybeEmitIrHintComment(snd);
  const std::string chan = SanitizeName(snd->channel_name());
  const std::string prog_send = ProgressLabel("send", chan);
  if (snd->predicate().has_value()) {
    Emit("if");
    if (options_.assert_send_on_full_channel)
      Emit(":: ($0 != 0) -> assert(len($1) < $2); $3$1 ! $4;",
           Ref(*snd->predicate()), chan, options_.channel_depth, prog_send,
           Ref(snd->data()));
    else
      Emit(":: ($0 != 0) -> $1$2 ! $3;", Ref(*snd->predicate()), prog_send,
           chan, Ref(snd->data()));
    Emit(":: else -> skip;");
    Emit("fi");
  } else {
    if (options_.assert_send_on_full_channel)
      Emit("assert(len($0) < $1);", chan, options_.channel_depth);
    Emit("$0$1 ! $2;", prog_send, chan, Ref(snd->data()));
  }
  return SetName(snd, "");
}

absl::Status PromelaGenerator::HandleAssert(Assert* a) {
  // Embed the IR label in a printf so the spin runner can identify which
  // assertion SPIN fires and compare it against the DSLX trace's assert_msgs.
  if (a->label().has_value() && !a->label()->empty()) {
    std::string label = *a->label();
    absl::StrReplaceAll({{"\\", "\\\\"}, {"\"", "\\\""}}, &label);
    Emit(absl::StrCat("printf(\"XLS_ASSERT:", label, "\\n\");"));
  }
  Emit("assert($0 != 0);", Ref(a->condition()));
  return SetName(a, "");
}

absl::Status PromelaGenerator::HandleInvoke(Invoke* inv) {
  const std::string var = Var(inv);
  Emit("$0 $1;", PromelaType(inv->GetType()), var);
  std::vector<std::string> arg_parts;
  for (int64_t i = 0; i < inv->operand_count(); ++i)
    arg_parts.emplace_back(Ref(inv->operand(i)));
  arg_parts.push_back(var);
  Emit("fn_$0($1);", SanitizeName(inv->to_apply()->name()),
       absl::StrJoin(arg_parts, ", "));
  return SetName(inv, var);
}

}  // namespace spin
}  // namespace xls
