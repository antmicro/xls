#!/usr/bin/env python3

import argparse
from rules_hdl.synthesis.power_performance_area_pb2 import PowerPerformanceAreaProto

from google.protobuf import text_format
from pathlib import Path


def parse_textproto_file(path):
    ppa = PowerPerformanceAreaProto()
    with open(path, 'r') as f:
        text_format.Parse(f.read(), ppa)
    return ppa


def remove_empty_keys(dicts):
    if not dicts:
        return []

    keys_to_keep = set()
    for d in dicts:
        for k, v in d.items():
            if v not in (None, "", [], {}):
                keys_to_keep.add(k)

    return [{k: v for k, v in d.items() if k in keys_to_keep} for d in dicts]


def print_table(data):
    headers = list(data[0].keys())
    # rows = [[row.get(key, "") for key in headers] for row in data]

    rows = []
    for d in data:
        row = []
        for key in headers:
            val = d.get(key, "")
            if isinstance(val, float):
                val = f"{val:.4f}"
            else:
                val = str(val)
            row.append(val)
        rows.append(row)

    cols = list(zip(*([headers] + rows)))
    col_widths = [max(len(str(cell)) for cell in col) for col in cols]

    def make_border():
       return "+" + "+".join("-" * (w + 2) for w in col_widths) + "+"

    def format_row(row):
        return "|" + "|".join(f" {str(cell).center(w)} " for cell, w in zip(row, col_widths)) + "|"

    print(make_border())
    print(format_row(headers))
    print(make_border())
    for row in rows:
        print(format_row(row))
    print(make_border())


def extract_area_fields(proto, file_path):
    area = proto.area
    if not area:
        return {}

    return {
        "file": file_path,
        "die_area_um2": area.die_area_um2 if area.HasField("die_area_um2") else None,
        "cell_area_um2": area.cell_area_um2 if area.HasField("cell_area_um2") else None,
        "die_height_um": area.die_height_um if area.HasField("die_height_um") else None,
        "die_width_um": area.die_width_um if area.HasField("die_width_um") else None,
        "cell_utilization_fraction": area.cell_utilization_fraction if area.HasField("cell_utilization_fraction") else None,
        "area_combinationals_um2": area.area_combinationals_um2 if area.HasField("area_combinationals_um2") else None,
        "area_buffers_um2": area.area_buffers_um2 if area.HasField("area_buffers_um2") else None,
        "area_timing_buffers_um2": area.area_timing_buffers_um2 if area.HasField("area_timing_buffers_um2") else None,
        "area_sequentials_um2": area.area_sequentials_um2 if area.HasField("area_sequentials_um2") else None,
        "area_inverters_um2": area.area_inverters_um2 if area.HasField("area_inverters_um2") else None,
        "area_macros_um2": area.area_macros_um2 if area.HasField("area_macros_um2") else None,
        "num_total_cells": area.num_total_cells if area.HasField("num_total_cells") else None,
        "num_combinational": area.num_combinational if area.HasField("num_combinational") else None,
        "num_buffers": area.num_buffers if area.HasField("num_buffers") else None,
        "num_timing_buffers": area.num_timing_buffers if area.HasField("num_timing_buffers") else None,
        "num_sequential": area.num_sequential if area.HasField("num_sequential") else None,
        "num_inverters": area.num_inverters if area.HasField("num_inverters") else None,
        "num_macros": area.num_macros if area.HasField("num_macros") else None,
    }


def extract_performance_fields(proto, file_path):
    perf = proto.performance
    if not perf:
        return {}
    fields = {
        "file": file_path,
        "clock_period_ps": perf.clock_period_ps if perf.HasField("clock_period_ps") else None,
        "critical_path_ps": perf.critical_path_ps if perf.HasField("critical_path_ps") else None,
        "fmax_ghz": perf.fmax_ghz if perf.HasField("fmax_ghz") else None,
        "setup_wns_ps": perf.setup_wns_ps if perf.HasField("setup_wns_ps") else None,
        "setup_tns_ps": perf.setup_tns_ps if perf.HasField("setup_tns_ps") else None,
        "hold_wns_ps": perf.hold_wns_ps if perf.HasField("hold_wns_ps") else None,
        "hold_tns_ps": perf.hold_tns_ps if perf.HasField("hold_tns_ps") else None,
        "clock_skew_ps": perf.clock_skew_ps if perf.HasField("clock_skew_ps") else None,
        "num_setup_violations": perf.num_setup_violations if perf.HasField("num_setup_violations") else None,
        "num_hold_violations": perf.num_hold_violations if perf.HasField("num_hold_violations") else None,
        "num_slew_violations": perf.num_slew_violations if perf.HasField("num_slew_violations") else None,
        "num_fanout_violations": perf.num_fanout_violations if perf.HasField("num_fanout_violations") else None,
        "num_capacitance_violations": perf.num_capacitance_violations if perf.HasField("num_capacitance_violations") else None,
        "longest_topological_path": perf.longest_topological_path if perf.HasField("longest_topological_path") else None,
        "critical_path_cells": perf.critical_path_cells if perf.HasField("critical_path_cells") else None,
    }

    def extract_timing_breakdown_fields(tb):
        if not tb:
            return {}
        return {
            "setup_wns_ps": tb.setup_wns_ps if tb.HasField("setup_wns_ps") else None,
            "setup_tns_ps": tb.setup_tns_ps if tb.HasField("setup_tns_ps") else None,
            "num_setup_violations": tb.num_setup_violations if tb.HasField("num_setup_violations") else None,
            "hold_wns_ps": tb.hold_wns_ps if tb.HasField("hold_wns_ps") else None,
            "hold_tns_ps": tb.hold_tns_ps if tb.HasField("hold_tns_ps") else None,
            "num_hold_violations": tb.num_hold_violations if tb.HasField("num_hold_violations") else None,
        }

    for tb_name in ["in2reg", "reg2reg", "reg2out", "in2out"]:
        tb = getattr(perf, tb_name)
        tb_fields = extract_timing_breakdown_fields(tb)
        for k, v in tb_fields.items():
            fields[f"{tb_name}({k})"] = v

    return fields


def extract_power_fields(proto, file_path):
  def extract_powerbreakdown_fields(pb):
    if not pb:
        return {}
    return {
        "total_watts": pb.total_watts if pb.HasField("total_watts") else "",
        "internal_watts": pb.internal_watts if pb.HasField("internal_watts") else "",
        "switching_watts": pb.switching_watts if pb.HasField("switching_watts") else "",
        "leakage_watts": pb.leakage_watts if pb.HasField("leakage_watts") else "",
    }

  power = proto.power
  if not power:
      return {}

  fields = {"file": file_path}
  for key in ["total", "sequential", "combinational", "macro", "pad", "clock"]:
      pb = getattr(power, key)
      pb_fields = extract_powerbreakdown_fields(pb)
      for k, v in pb_fields.items():
          fields[f"{key}({k})"] = v

  fields["estimation_method"] = power.estimation_method if power.HasField("estimation_method") else ""
  return fields

def extract_summary(proto, file_path):
    return {
        "file": file_path,
        "cell_area": proto.area.cell_area_um2,
        "util_frac": proto.area.cell_utilization_fraction,
        "total_cells": proto.area.num_total_cells,
        "fmax_ghz": proto.performance.fmax_ghz,
        "clock_ps": proto.performance.clock_period_ps,
        "wns_ps": proto.performance.setup_wns_ps,
        "tns_ps": proto.performance.setup_tns_ps,
        "power_total": proto.power.total.total_watts,
    }

def main():
    parser = argparse.ArgumentParser(description="Process one or more input files")
    parser.add_argument("files", nargs="+",  help="Input file(s) to process")
    args = parser.parse_args()

    # collect data
    area_data = []
    performance_data = []
    power_data = []
    for file_path in args.files:
        file_name = Path(file_path).name
        msg = parse_textproto_file(file_path)
        performance = extract_performance_fields(msg, file_name)
        performance_data.append(performance)
        area = extract_area_fields(msg, file_name)
        area_data.append(area)
        power = extract_power_fields(msg, file_name)
        power_data.append(power)


    # print data
    has_more_keys = lambda dicts: any(len(d) > 1 for d in dicts)

    small_area_data = remove_empty_keys(area_data)
    if has_more_keys(small_area_data):
      print("\n### 1. AREA \n")
      print_table(small_area_data)

    small_performance_data = remove_empty_keys(performance_data)
    if has_more_keys(small_performance_data):
      print("\n### 2. PERFORMANCE\n")
      print_table(small_performance_data)

    small_power_data = remove_empty_keys(power_data)
    if has_more_keys(small_power_data):
      print("\n### 3. POWER\n")
      print_table(small_power_data)


if __name__ == "__main__":
    main()
