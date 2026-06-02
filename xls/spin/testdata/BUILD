# Copyright 2026 The XLS Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Golden IR diff tests for xls/spin testdata.

load("//xls/spin:priv-defs.bzl", "spin_ir_golden_test")

package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_internal"],
    licenses = ["notice"],
)

exports_files(glob(["*.ir", "*.x"]))

spin_ir_golden_test(
    name = "assertion_ir_golden",
    src = "assertion.x",
    golden = "assertion.ir",
    dslx_top = "Asserting",
)

spin_ir_golden_test(
    name = "blocking_receive_ir_golden",
    src = "blocking_receive.x",
    golden = "blocking_receive.ir",
    dslx_top = "Reader",
)

spin_ir_golden_test(
    name = "conditional_io_ir_golden",
    src = "conditional_io.x",
    golden = "conditional_io.ir",
    dslx_top = "ConditionalIoTest",
    convert_tests = True,
)

spin_ir_golden_test(
    name = "counter_ir_golden",
    src = "counter.x",
    golden = "counter.ir",
    dslx_top = "CounterTest",
    convert_tests = True,
)

spin_ir_golden_test(
    name = "multi_proc_ir_golden",
    src = "multi_proc.x",
    golden = "multi_proc.ir",
    dslx_top = "ProcA",
)

spin_ir_golden_test(
    name = "non_blocking_receive_ir_golden",
    src = "non_blocking_receive.x",
    golden = "non_blocking_receive.ir",
    dslx_top = "NbReader",
)

spin_ir_golden_test(
    name = "passthrough_ir_golden",
    src = "passthrough.x",
    golden = "passthrough.ir",
    dslx_top = "PassthroughTest",
    convert_tests = True,
)

spin_ir_golden_test(
    name = "predicated_receive_ir_golden",
    src = "predicated_receive.x",
    golden = "predicated_receive.ir",
    dslx_top = "CondReader",
)

spin_ir_golden_test(
    name = "predicated_send_ir_golden",
    src = "predicated_send.x",
    golden = "predicated_send.ir",
    dslx_top = "CondWriter",
)

spin_ir_golden_test(
    name = "func_ir_golden",
    src = "func.x",
    golden = "func.ir",
    dslx_top = "myfunc",
)

spin_ir_golden_test(
    name = "proc_ir_golden",
    src = "proc.x",
    golden = "proc.ir",
    dslx_top = "MyProc",
)

spin_ir_golden_test(
    name = "state_counter_ir_golden",
    src = "state_counter.x",
    golden = "state_counter.ir",
    dslx_top = "Counter",
)

spin_ir_golden_test(
    name = "unconditional_send_ir_golden",
    src = "unconditional_send.x",
    golden = "unconditional_send.ir",
    dslx_top = "Writer",
)

spin_ir_golden_test(
    name = "xr_xs_hints_ir_golden",
    src = "xr_xs_hints.x",
    golden = "xr_xs_hints.ir",
    dslx_top = "RwProc",
)

spin_ir_golden_test(
    name = "channel_naming_ir_golden",
    src = "channel_naming.x",
    golden = "channel_naming.ir",
    dslx_top = "MultiplyBy4Test",
    convert_tests = True,
)

spin_ir_golden_test(
    name = "deadlock_ir_golden",
    src = "deadlock.x",
    golden = "deadlock.ir",
    dslx_top = "Test",
    convert_tests = True,
)
