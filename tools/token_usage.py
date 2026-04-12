#!/usr/bin/env python3
"""
Summarize Ollama token usage from ~/Library/Logs/AgentKVT/token_usage.jsonl

Usage:
  python3 tools/token_usage.py            # today + all-time summary
  python3 tools/token_usage.py --all      # all-time only
  python3 tools/token_usage.py --tail 20  # last N calls (detailed)
  python3 tools/token_usage.py --by-task  # break down savings by task
"""

import json
import sys
import os
from collections import defaultdict
from datetime import date

LOG_PATH = os.path.expanduser("~/Library/Logs/AgentKVT/token_usage.jsonl")


def load_entries():
    if not os.path.exists(LOG_PATH):
        print(f"No log file found at {LOG_PATH}")
        print("Run some agent tasks first to generate data.")
        sys.exit(0)
    entries = []
    with open(LOG_PATH) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
                # Normalize both old schema (input_tokens) and new schema (tokens.in)
                if "tokens" in e:
                    e["_in"]  = e["tokens"].get("in", 0)
                    e["_out"] = e["tokens"].get("out", 0)
                else:
                    e["_in"]  = e.get("input_tokens", 0)
                    e["_out"] = e.get("output_tokens", 0)
                e["_savings"] = e.get("savings_usd", 0.0)
                e["_latency"] = e.get("latency_ms", None)
                e["_task"]    = e.get("task", "unknown")
                entries.append(e)
            except json.JSONDecodeError:
                pass
    return entries


def fmt(n):
    return f"{n:,}"


def print_summary(entries, label):
    if not entries:
        print(f"\nNo entries for: {label}")
        return

    total_in      = sum(e["_in"]      for e in entries)
    total_out     = sum(e["_out"]     for e in entries)
    total_savings = sum(e["_savings"] for e in entries)
    calls         = len(entries)

    latencies = [e["_latency"] for e in entries if e["_latency"] is not None]
    avg_latency = int(sum(latencies) / len(latencies)) if latencies else None

    by_model = defaultdict(lambda: {"calls": 0, "in": 0, "out": 0, "savings": 0.0})
    for e in entries:
        m = e.get("model", "unknown")
        by_model[m]["calls"]   += 1
        by_model[m]["in"]      += e["_in"]
        by_model[m]["out"]     += e["_out"]
        by_model[m]["savings"] += e["_savings"]

    print(f"\n{'='*52}")
    print(f"  Token Usage — {label}")
    print(f"{'='*52}")
    print(f"  LLM calls     : {fmt(calls)}")
    print(f"  Input tokens  : {fmt(total_in)}")
    print(f"  Output tokens : {fmt(total_out)}")
    print(f"  Total tokens  : {fmt(total_in + total_out)}")
    if calls > 0:
        print(f"  Avg/call      : {fmt((total_in + total_out) // calls)} tokens")
    if avg_latency is not None:
        print(f"  Avg latency   : {fmt(avg_latency)} ms")
    print(f"  Savings (vs ☁️) : ${total_savings:.4f}")
    print()
    print("  By model:")
    for model, s in sorted(by_model.items()):
        print(f"    {model}")
        print(f"      calls={fmt(s['calls'])}  in={fmt(s['in'])}  out={fmt(s['out'])}  saved=${s['savings']:.4f}")
    print()


def print_by_task(entries):
    by_task = defaultdict(lambda: {"calls": 0, "in": 0, "out": 0, "savings": 0.0, "latencies": []})
    for e in entries:
        t = e["_task"]
        by_task[t]["calls"]   += 1
        by_task[t]["in"]      += e["_in"]
        by_task[t]["out"]     += e["_out"]
        by_task[t]["savings"] += e["_savings"]
        if e["_latency"] is not None:
            by_task[t]["latencies"].append(e["_latency"])

    print(f"\n{'='*52}")
    print(f"  Savings by Task (all time)")
    print(f"{'='*52}")
    rows = sorted(by_task.items(), key=lambda x: x[1]["savings"], reverse=True)
    for task, s in rows:
        avg_lat = int(sum(s["latencies"]) / len(s["latencies"])) if s["latencies"] else None
        lat_str = f"  avg_lat={fmt(avg_lat)}ms" if avg_lat else ""
        print(f"  {task:<30} calls={fmt(s['calls']):>6}  saved=${s['savings']:.4f}{lat_str}")
    print()


def print_tail(entries, n):
    tail = entries[-n:]
    print(f"\nLast {len(tail)} calls:\n")
    print(f"  {'Timestamp':<20} {'Task':<25} {'Model':<18} {'In':>7} {'Out':>7} {'ms':>6} {'Saved':>8}")
    print(f"  {'-'*20} {'-'*25} {'-'*18} {'-'*7} {'-'*7} {'-'*6} {'-'*8}")
    for e in tail:
        ts      = e.get("ts", "?")[:19].replace("T", " ")
        task    = e["_task"][:25]
        model   = e.get("model", "?")[:18]
        lat     = fmt(e["_latency"]) if e["_latency"] else "  —"
        savings = f"${e['_savings']:.4f}"
        print(f"  {ts:<20} {task:<25} {model:<18} {e['_in']:>7,} {e['_out']:>7,} {lat:>6} {savings:>8}")
    print()


def main():
    args = sys.argv[1:]
    entries = load_entries()

    if "--tail" in args:
        idx = args.index("--tail")
        n = int(args[idx + 1]) if idx + 1 < len(args) else 20
        print_tail(entries, n)
        return

    if "--by-task" in args:
        print_by_task(entries)
        return

    if "--all" in args:
        print_summary(entries, "All Time")
        return

    today = date.today().isoformat()
    today_entries = [e for e in entries if e.get("ts", "").startswith(today)]
    print_summary(today_entries, f"Today ({today})")
    print_summary(entries, "All Time")


if __name__ == "__main__":
    main()
