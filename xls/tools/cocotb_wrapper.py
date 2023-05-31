#!/usr/bin/env python3

import sys
import os.path

from absl import app
from absl import flags

from cocotb.runner import get_runner

FLAGS = flags.FLAGS

flags.DEFINE_string("sim", "icarus", "Dafault simulator")
flags.DEFINE_string("action", None, "Action to take possible: build, test")

# cocotb common (build and test) flags
flags.DEFINE_string("toplevel", None, "Name of the HDL toplevel module")
flags.DEFINE_list("parameters", None, "Verilog parameters or VHDL generics")
flags.DEFINE_string("build_dir", None, "Directory to run the build step in")

cocotb_common_flags = [
    "toplevel",
    "parameters",
    "build_dir"
]

# cocotb build flags
flags.DEFINE_string("library_name", None, "The library name to compile into")
flags.DEFINE_list("verilog_sources", None, "Verilog source files to build")
flags.DEFINE_list("vhdl_sources", None, "VHDL source files to build")
flags.DEFINE_list("includes", None, "Verilog include directories")
flags.DEFINE_list("defines", None, "Defines to set")
flags.DEFINE_list("build_args", None, "Extra build arguments for the simulator")

cocotb_build_flags = [
    "library_name",
    "verilog_sources",
    "vhdl_sources",
    "includes",
    "defines",
    "build_args",
]

# coctb sim flags
flags.DEFINE_string("toplevel_lang", None, "Language of the HDL toplevel module")
flags.DEFINE_string("testcase", None, "Name(s) of a specific testcase(s) to run")
flags.DEFINE_string("seed", None, "A specific random seed to use")
flags.DEFINE_list("extra_args", None, "Extra arguments for the simulator")
flags.DEFINE_list("plus_args", None, "Plusargs' to set for the simulator")
flags.DEFINE_list("extra_env", None, "Extra environment variables to set")
flags.DEFINE_bool("waves", None, "Record signal traces")
flags.DEFINE_string("sim_dir", None, "Directory the build step has been run in")
flags.DEFINE_string("py_module", None, "Cocotb python module with tests")

cocotb_test_flags = [
    "toplevel_lang",
    "testcase",
    "seed",
    "extra_args",
    "plus_args",
    "extra_env",
    "sim_dir",
    "py_module",
]


def filter_keys(key_list, dict_to_filter):
    result = {}
    for key in key_list:
        if key in dict_to_filter:
            result.update({key: dict_to_filter[key]})
    return result


def main(argv):

    runner = get_runner(FLAGS.sim)()

    runner_kwargs = dict()
    for flag in FLAGS.get_flags_for_module(__file__):
        if flag.name in ["sim", "action"] or flag.value is None:
            continue
        if flag.name == "py_module":
            dirname = os.path.dirname(FLAGS.py_module)
            filename = os.path.splitext(os.path.basename(FLAGS.py_module))[0]
            sys.path.append(dirname)
            runner_kwargs.update({flag.name: filename})
        elif flag.name in ["parameters", "extra_env"]:
            data = getattr(FLAGS, flag.name)
            if data is not None:
                data_pairs = [x.split(":") for x in data]
                data_dict = {key: value for key, value in data_pairs}
                runner_kwargs.update({flag.name: data_dict})
        else:
            value = getattr(FLAGS, flag.name)
            if value is not None:
                runner_kwargs.update({flag.name: value})

    common_kwargs = filter_keys(cocotb_common_flags, runner_kwargs)
    build_kwargs = filter_keys(cocotb_build_flags, runner_kwargs)
    test_kwargs = filter_keys(cocotb_test_flags, runner_kwargs)

    if FLAGS.action == "build":
        assert len(test_kwargs) == 0
        runner.build(**common_kwargs, **build_kwargs)
    elif FLAGS.action == "test":
        assert len(build_kwargs) == 0
        runner.test(**common_kwargs, **test_kwargs)


if __name__ == '__main__':
    app.run(main)
