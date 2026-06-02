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

# Build rules for XLS spin examples.

load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_test",
)
load(
    "//xls/spin:defs.bzl",
    "spin_run",
    "spin_test",
    "xls_dslx_spin",
)

package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_internal"],
    licenses = ["notice"],
)

exports_files(glob(include = ["*.x"]))

# ---------------------------------------------------------------------------
# counter
# ---------------------------------------------------------------------------

xls_dslx_library(
    name = "counter_dslx",
    srcs = ["counter.x"],
)

xls_dslx_test(
    name = "counter_dslx_test",
    library = ":counter_dslx",
    spin_verify = True,
)

xls_dslx_spin(
    name = "counter_pml",
    srcs = ["counter.x"],
    dslx_top = "CounterTest",
    emit_termination_hook = True,
)

spin_run(
    name = "counter_run",
    src = ":counter_pml",
)

spin_test(
    name = "counter_pml_verify",
    src = ":counter_pml",
)

# ---------------------------------------------------------------------------
# order_dependence
# ---------------------------------------------------------------------------

xls_dslx_library(
    name = "order_dependence_dslx",
    srcs = ["order_dependence.x"],
)

xls_dslx_test(
    name = "order_dependence_dslx_test",
    library = ":order_dependence_dslx",
    spin_verify = True,
)

xls_dslx_spin(
    name = "order_dependence_pml",
    srcs = ["order_dependence.x"],
    dslx_top = "Tester",
    emit_termination_hook = True,
)

spin_run(
    name = "order_dependence_run",
    src = ":order_dependence_pml",
)

# Exhaustive search is expected to fail here: the assertion in Tester is not
# invariant under every SPIN interleaving (see README.md), unlike the single
# simulation run that --spin_verify compares against the DSLX interpreter.
spin_test(
    name = "order_dependence_pml_verify",
    src = ":order_dependence_pml",
    tags = ["manual"],
)

# ---------------------------------------------------------------------------
# deadlock -- no trace comparison; the model deadlocks by design
# ---------------------------------------------------------------------------

xls_dslx_library(
    name = "deadlock_dslx",
    srcs = ["deadlock.x"],
)

xls_dslx_test(
    name = "deadlock_dslx_test",
    library = ":deadlock_dslx",
)

xls_dslx_spin(
    name = "deadlock_pml",
    srcs = ["deadlock.x"],
    dslx_top = "Test",
    emit_termination_hook = True,
    opt = False,
)

spin_run(
    name = "deadlock_run",
    src = ":deadlock_pml",
)

spin_test(
    name = "deadlock_pml_verify",
    src = ":deadlock_pml",
    tags = ["manual"],
)
