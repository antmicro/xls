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

#ifndef XLS_SPIN_PROMELA_GENERATOR_H_
#define XLS_SPIN_PROMELA_GENERATOR_H_

#include <string>
#include <string_view>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/substitute.h"
#include "xls/ir/dfs_visitor.h"
#include "xls/ir/package.h"

namespace xls {
namespace spin {

struct PromelaGeneratorOptions {
  // Annotate each Promela statement with a /* filename:line:col */ comment.
  bool emit_source_locations = false;

  // Annotate each Promela statement with a /* ir: <node-expr> */ comment.
  bool emit_source_hints = false;

  // Buffer depth N in `chan x = [N] of {T}`. Default 8.
  int channel_depth = 8;

  // Block init on the terminator channel (mirrors #[test_proc]).
  bool emit_termination_hook = false;

  // Prefix every send with `assert(len(ch) < DEPTH)` to turn a full-channel
  // block into an explicit SPIN assertion violation.
  bool assert_send_on_full_channel = false;

  // Maps sanitised proc name to N: proc does real work at most once every N
  // loop iterations; other iterations are idle stalls. Procs not listed use 1.
  absl::flat_hash_map<std::string, int> worst_case_throughput;

  // Prefix each channel send/receive with a SPIN progress label for livelock
  // detection via `spin -search -DNP`.
  bool emit_progress_labels = false;
};

// Translates an XLS IR package to Promela source text.
//
// Derives from DfsVisitorWithDefault: each XLS node is visited in DFS
// post-order and emitted as one or more Promela statements. Call the static
// Generate() factory to run a full translation; do not instantiate directly.
class PromelaGenerator : public DfsVisitorWithDefault {
 public:
  // Translates all functions and procs in `package` into Promela source text.
  // Requires proc-scoped channels; returns an error for old-style packages.
  static absl::StatusOr<std::string> Generate(
      Package* package,
      const PromelaGeneratorOptions& options = PromelaGeneratorOptions{});

  // DfsVisitorWithDefault overrides.
  absl::Status DefaultHandler(Node* node) override;
  absl::Status HandleAfterAll(AfterAll* n) override;
  absl::Status HandleMinDelay(MinDelay* n) override;
  absl::Status HandleTrace(Trace* n) override;
  absl::Status HandleCover(Cover* n) override;
  absl::Status HandleNewChannel(NewChannel* n) override;
  absl::Status HandleRecvChannelEnd(RecvChannelEnd* n) override;
  absl::Status HandleSendChannelEnd(SendChannelEnd* n) override;
  absl::Status HandleParam(Param* param) override;
  absl::Status HandleStateRead(StateRead* sr) override;
  absl::Status HandleNext(Next* next) override;
  absl::Status HandleLiteral(Literal* lit) override;
  absl::Status HandleAdd(BinOp* add) override;
  absl::Status HandleSub(BinOp* sub) override;
  absl::Status HandleUMul(ArithOp* mul) override;
  absl::Status HandleSMul(ArithOp* mul) override;
  absl::Status HandleUDiv(BinOp* div) override;
  absl::Status HandleSDiv(BinOp* div) override;
  absl::Status HandleUMod(BinOp* mod) override;
  absl::Status HandleSMod(BinOp* mod) override;
  absl::Status HandleNeg(UnOp* neg) override;
  absl::Status HandleIdentity(UnOp* id) override;
  absl::Status HandleNot(UnOp* not_op) override;
  absl::Status HandleNaryAnd(NaryOp* n) override;
  absl::Status HandleNaryOr(NaryOp* n) override;
  absl::Status HandleNaryXor(NaryOp* n) override;
  absl::Status HandleNaryNand(NaryOp* n) override;
  absl::Status HandleNaryNor(NaryOp* n) override;
  absl::Status HandleAndReduce(BitwiseReductionOp* n) override;
  absl::Status HandleOrReduce(BitwiseReductionOp* n) override;
  absl::Status HandleShll(BinOp* n) override;
  absl::Status HandleShrl(BinOp* n) override;
  absl::Status HandleShra(BinOp* n) override;
  absl::Status HandleEq(CompareOp* n) override;
  absl::Status HandleNe(CompareOp* n) override;
  absl::Status HandleULt(CompareOp* n) override;
  absl::Status HandleULe(CompareOp* n) override;
  absl::Status HandleUGt(CompareOp* n) override;
  absl::Status HandleUGe(CompareOp* n) override;
  absl::Status HandleSLt(CompareOp* n) override;
  absl::Status HandleSLe(CompareOp* n) override;
  absl::Status HandleSGt(CompareOp* n) override;
  absl::Status HandleSGe(CompareOp* n) override;
  absl::Status HandleBitSlice(BitSlice* bs) override;
  absl::Status HandleDynamicBitSlice(DynamicBitSlice* dbs) override;
  absl::Status HandleSignExtend(ExtendOp* ext) override;
  absl::Status HandleZeroExtend(ExtendOp* ext) override;
  absl::Status HandleConcat(Concat* concat) override;
  absl::Status HandleSel(Select* sel) override;
  absl::Status HandleOneHotSel(OneHotSelect* ohs) override;
  absl::Status HandlePrioritySel(PrioritySelect* ps) override;
  absl::Status HandleGate(Gate* gate) override;
  absl::Status HandleTuple(Tuple* tuple) override;
  absl::Status HandleTupleIndex(TupleIndex* ti) override;
  absl::Status HandleReceive(Receive* recv) override;
  absl::Status HandleSend(Send* snd) override;
  absl::Status HandleAssert(Assert* a) override;
  absl::Status HandleInvoke(Invoke* inv) override;

  // Ops with no Promela equivalent; DfsVisitorWithDefault routes these to
  // DefaultHandler which returns UnimplementedError for data-carrying nodes.
  //
  // absl::Status HandleInputPort(InputPort* n) override;
  // absl::Status HandleOutputPort(OutputPort* n) override;
  // absl::Status HandleInstantiationInput(InstantiationInput* n) override;
  // absl::Status HandleInstantiationOutput(InstantiationOutput* n) override;
  // absl::Status HandleRegisterRead(RegisterRead* n) override;
  // absl::Status HandleRegisterWrite(RegisterWrite* n) override;
  // absl::Status HandleXorReduce(BitwiseReductionOp* n) override;
  // absl::Status HandleReverse(UnOp* n) override;
  // absl::Status HandleOneHot(OneHot* n) override;
  // absl::Status HandleArray(Array* n) override;
  // absl::Status HandleArrayConcat(ArrayConcat* n) override;
  // absl::Status HandleArrayIndex(ArrayIndex* n) override;
  // absl::Status HandleArraySlice(ArraySlice* n) override;
  // absl::Status HandleArrayUpdate(ArrayUpdate* n) override;
  // absl::Status HandleMap(Map* n) override;
  // absl::Status HandleCountedFor(CountedFor* n) override;
  // absl::Status HandleDynamicCountedFor(DynamicCountedFor* n) override;
  // absl::Status HandleBitSliceUpdate(BitSliceUpdate* n) override;
  // absl::Status HandleEncode(Encode* n) override;
  // absl::Status HandleDecode(Decode* n) override;
  // absl::Status HandleSMulp(PartialProductOp* n) override;
  // absl::Status HandleUMulp(PartialProductOp* n) override;

 private:
  // Indented-line emitter. Each indent level adds two spaces.
  class Emitter {
   public:
    explicit Emitter(std::string& out, int level = 0)
        : out_(out), level_(level) {}
    void Reset() { level_ = 0; }
    void Indent() { ++level_; }
    void Dedent() {
      if (level_ > 0) --level_;
    }
    void Blank() { out_ += '\n'; }
    void Line(absl::string_view text) {
      WriteIndent();
      absl::StrAppend(&out_, text, "\n");
    }
    template <typename... Args>
    void Line(absl::string_view fmt, const Args&... args) {
      WriteIndent();
      absl::SubstituteAndAppend(&out_, fmt, args...);
      out_ += '\n';
    }

   private:
    void WriteIndent() {
      for (int i = 0; i < level_; ++i) absl::StrAppend(&out_, "  ");
    }
    std::string& out_;
    int level_;
  };

  explicit PromelaGenerator(Package* package,
                            const PromelaGeneratorOptions& options);

  // Package-level orchestration.
  absl::Status ValidateTypes();
  std::vector<Proc*> FindRootProcs() const;
  absl::Status EmitFunction(Function* fn);
  absl::Status EmitProc(Proc* proc);
  void EmitInit(const std::vector<Proc*>& root_procs);

  // Node name tracking.
  absl::Status SetName(Node* node, std::string name);
  std::string_view Ref(Node* node) const;
  std::string Var(Node* node) const;

  // Code emission helpers.
  absl::Status Assign(Node* node, std::string_view expr);
  absl::Status EmitCompare(CompareOp* node, std::string_view cmp_op);
  absl::Status EmitNaryBitwise(NaryOp* node, std::string_view op_sym,
                               bool invert = false);
  absl::Status EmitBitwiseReduce(BitwiseReductionOp* node,
                                 std::string_view cmp_op,
                                 std::string_view sentinel);
  absl::Status EmitMul(ArithOp* mul);
  std::string ProgressLabel(std::string_view dir, std::string_view chan) const;
  void MaybeEmitLocComment(Node* node);
  void MaybeEmitIrHintComment(Node* node);

  void Emit(absl::string_view text) { emit_.Line(text); }
  template <typename... Args>
  void Emit(absl::string_view fmt, const Args&... args) {
    emit_.Line(fmt, args...);
  }

  Package* package_;
  PromelaGeneratorOptions options_;
  std::string out_;
  Emitter emit_;

  // Per-FunctionBase visit state; set up in EmitFunction / EmitProc.
  absl::flat_hash_map<Node*, std::string> names_;
  absl::flat_hash_map<Node*, std::vector<std::string>> tuple_components_;
  // Collects Next nodes during proc visits for deferred state-update emit.
  std::vector<Node*> next_nodes_;
};

}  // namespace spin
}  // namespace xls

#endif  // XLS_SPIN_PROMELA_GENERATOR_H_
