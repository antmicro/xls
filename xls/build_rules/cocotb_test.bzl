# Copyright 2020 The XLS Authors
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

"""Contains internal XLS macros."""

load(
    "//xls/build_rules:xls_type_check_helpers.bzl",
    "dictionary_type_check",
    "list_type_check",
    "string_type_check",
)


def _create_cmd_from_string(name, value):
    if value != None:
        return " --{}={}".format(name, value)
    else:
        return ""


def _create_cmd_from_filelist(name, filelist):
    if filelist != None and len(filelist) != 0:
        srcs_str = ""
        for i, src in enumerate(filelist):
            srcs_str += "" if i == 0 else ","
            srcs_str += "$(location {})".format(src)
        return " --{}={}".format(name, srcs_str)
    else:
        return ""


def _create_cmd_from_list(name, data):
    if data != None and len(data) != 0:
        items_str = ""
        for i, item in enumerate(data):
            items_str += "" if i == 0 else ","
            items_str += "{}".format(item)
        return " --{}={}".format(name, items_str)
    else:
        return ""


def _create_cmd_from_dict(name, data):
    if data != None and len(data) != 0:
        items_str = ""
        for i, (key, value) in enumerate(data.items()):
            items_str += "" if i == 0 else ","
            items_str += "{}:{}".format(key, value)
        return " --{}={}".format(name, items_str)
    else:
        return ""


def _create_build_cmd(top, sim, library_name, verilog_srcs, vhdl_srcs,
        includes, defines, parameters, build_args):

    cmd = "$(location //xls/tools:cocotb_wrapper) --action=build "
    cmd += " --toplevel={}".format(top)
    cmd += " --build_dir=$(@D)"

    cmd += _create_cmd_from_string("sim", sim)
    cmd += _create_cmd_from_string("library_name", library_name)
    cmd += _create_cmd_from_filelist("verilog_sources", verilog_srcs)
    cmd += _create_cmd_from_filelist("vhdl_sources", vhdl_srcs)
    cmd += _create_cmd_from_list("includes", includes)
    cmd += _create_cmd_from_list("defines", defines)
    cmd += _create_cmd_from_dict("parameters", parameters)
    cmd += _create_cmd_from_list("build_args", build_args)

    return cmd


def _create_simulation_cmd(top, sim, toplevel_lang, testcase, seed, extra_args,
    plus_args, extra_env, parameters, sim_dir, py_module_target):

    cmd = "$(location //xls/tools:cocotb_wrapper) --action=test"
    cmd += " --toplevel=%s" % (top)
    cmd += " --build_dir=$(RULEDIR)/{}".format(sim_dir)
    cmd += " --sim_dir=."
    cmd += " --py_module=$(location {})".format(py_module_target)

    cmd += _create_cmd_from_string("sim", sim)
    cmd += _create_cmd_from_string("toplevel", top)
    cmd += _create_cmd_from_string("toplevel_lang", toplevel_lang)
    cmd += _create_cmd_from_string("testcase", testcase)
    cmd += _create_cmd_from_string("seed", seed)
    cmd += _create_cmd_from_list("extra_args", extra_args)
    cmd += _create_cmd_from_list("plus_args", plus_args)
    cmd += _create_cmd_from_dict("extra_env", extra_env)
    cmd += _create_cmd_from_dict("parameters", parameters)

    return cmd


def _create_test_cmd(top, sim, toplevel_lang, testcase, seed, extra_args,
    plus_args, extra_env, parameters, sim_dir, py_module_target):

    cmd = _create_simulation_cmd(
        top, sim, toplevel_lang, testcase, seed, extra_args,
        plus_args, extra_env, parameters, sim_dir, py_module_target
    )
    cmd = "echo {} | sed s?bazel-out/[^/]*/bin/??g >> $@ ".format(cmd)

    return cmd


def _get_vcddump_str(dumpfile, top):
    return """cat << EOF > $@
module wave_dump();
initial begin
    \\$$dumpfile("{}");
    \\$$dumpvars(0, {});
end
endmodule
EOF
""".format(dumpfile, top)


def _cocotb_macro(
    name,
    top,
    sim,
    test_module,
    verilog_srcs=[],
    vhdl_srcs=[],
    includes=[],
    defines=[],
    parameters={},
    build_args=[],
    extra_args=[],
    plus_args=[],
    extra_env={},
    timescale={},
    testcase=None,
    library_name=None,
    seed=None,
    toplevel_lang="verilog",

    wave=False,
    use_test_genrules=True
):

    string_type_check("name", name)
    string_type_check("top", top)
    string_type_check("sim", sim)
    string_type_check("test_module", test_module)
    string_type_check("library_name", library_name, True)
    list_type_check("verilog_srcs", verilog_srcs, True)
    list_type_check("vhdl_srcs", vhdl_srcs, True)
    list_type_check("includes", includes, True)
    list_type_check("defines", defines, True)
    dictionary_type_check("parameters", parameters, True)
    list_type_check("build_args", build_args, True)

    if not use_test_genrules and wave:
        dumpvcd = name + "_dump.vcd"
        dumpvcd_path = "$(RULEDIR)/" + dumpvcd
        dumpvcd_target = name + "-dumpvcd"
        dumpvcd_verilog = name + "_dumpvcd.v"

        native.genrule(
            name = dumpvcd_target,
            srcs = [],
            cmd = _get_vcddump_str(dumpvcd_path, top),
            outs = [ dumpvcd_verilog ],
        )
        verilog_srcs.insert(0, dumpvcd_verilog)

    if timescale != None:
        timestamp_target = name + "-timescale"
        timestamp_verilog = name + "_timescale.v"
        native.genrule(
            name = timestamp_target,
            srcs = [],
            cmd = "echo \\`timescale {}/{} > $@".format(
                timescale["unit"],
                timescale["precission"]
            ),
            outs = [ timestamp_verilog ],

        )
        verilog_srcs.insert(0, timestamp_verilog)

    py_module_target = name + "-module"
    native.genrule(
        name = py_module_target,
        srcs = [test_module],
        cmd = "cp $< $@",
        outs = [
            name + "_" + test_module,
        ],
    )

    sim_dir = name + "-sim_build"
    build_target = name + "-build"
    native.genrule(
        name = build_target,
        srcs = verilog_srcs + vhdl_srcs,
        cmd = _create_build_cmd(
            top, sim, library_name, verilog_srcs, vhdl_srcs, includes,
            defines, parameters, build_args
        ),
        outs = [
            "{}/sim.vvp".format(sim_dir),
        ],
        tools = [
            "//xls/tools:cocotb_wrapper",
            "@com_icarus_iverilog//:iverilog",
        ]
    )

    if use_test_genrules:
        runner_target = name + "-runner"
        runner_script = name + "_runner.sh"
        native.genrule(
            name = runner_target,
            srcs = [
                py_module_target,
                build_target
            ],
            cmd = _create_test_cmd(
                top, sim, toplevel_lang, testcase, seed, extra_args, plus_args,
                extra_env, parameters, sim_dir, py_module_target
            ),
            outs = [ runner_script ],
            tools = [
                "//xls/tools:cocotb_wrapper",
                "@com_icarus_iverilog//:iverilog",
            ],
        )

        test_target = name + "-test"
        native.sh_test(
            name = test_target,
            srcs = [ runner_target ],
            data = [
                "//xls/tools:cocotb_wrapper",
                py_module_target,
                build_target
            ],
        )

        native.test_suite(
            name = name,
            tests = [
                test_target,
            ],
        )
    else:
        simulation_target = name + "-simulate"
        native.genrule(
            name = simulation_target,
            srcs = [
                py_module_target,
                build_target
            ],
            cmd = _create_simulation_cmd(
                top, sim, toplevel_lang, testcase, seed, extra_args, plus_args,
                extra_env, parameters, sim_dir, py_module_target
            ),
            outs = [ dumpvcd ],
            tools = [
                "//xls/tools:cocotb_wrapper",
                "@com_icarus_iverilog//:iverilog",
            ],
        )

# macro for adding cocotb tests executed with `bazel test`
def cocotb_test(
    name, # name of the rule
    top, # top-level name
    sim, # simulator to use
    test_module, # cocotb python module with tests
    verilog_srcs=[], # list of verilog sources to build
    vhdl_srcs=[], # list of vhdl sources to build
    includes=[], # list of include directories
    defines=[], # list of defines to set
    parameters={}, # list of parameters or vhdl generics
    build_args=[], # extra cocotb builder arguments
    extra_args=[], # extra arguments for the simulator
    plus_args=[], # plusargs for the simulator
    extra_env={}, # extra environment variables for the simulator
    timescale={}, # timescale to use expected keys: "unit", "precission"
    testcase=None, # name of testcase to run (unspecified means all)
    library_name=None, # vhdl library name to compile into
    seed=None, # seed for the simulator
    toplevel_lang="verilog", # language of top-level
):
    _cocotb_macro(name, top, sim, test_module, verilog_srcs, vhdl_srcs,
        includes, defines, parameters, build_args, extra_args, plus_args,
        extra_env, timescale, testcase, library_name, seed, toplevel_lang,
        wave=False, use_test_genrules=True
    )

# macro for running the entire simulation and to obtain a trace
def cocotb_simulate(
    name, # name of the rule
    top, # top-level name
    sim, # simulator to use
    test_module, # cocotb python module with tests
    verilog_srcs=[], # list of verilog sources to build
    vhdl_srcs=[], # list of vhdl sources to build
    includes=[], # list of include directories
    defines=[], # list of defines to set
    parameters={}, # list of parameters or vhdl generics
    build_args=[], # extra cocotb builder arguments
    extra_args=[], # extra arguments for the simulator
    plus_args=[], # plusargs for the simulator
    extra_env={}, # extra environment variables for the simulator
    timescale={}, # timescale to use expected keys: "unit", "precission"
    testcase=None, # name of testcase to run (unspecified means all)
    library_name=None, # vhdl library name to compile into
    seed=None, # seed for the simulator
    toplevel_lang="verilog", # language of top-level
    wave=True, # if generate vcd files
):
    _cocotb_macro(name, top, sim, test_module, verilog_srcs, vhdl_srcs,
        includes, defines, parameters, build_args, extra_args, plus_args,
        extra_env, timescale, testcase, library_name, seed, toplevel_lang,
        wave, use_test_genrules=False
    )
