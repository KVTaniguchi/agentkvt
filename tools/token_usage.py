#!/usr/bin/env python3
"""
Summarize Ollama token usage from ~/Library/Logs/AgentKVT/token_usage.jsonl

Usage:
  python3 tools/token_usage.py            # today's summary
  python3 tools/token_usage.py --all      # all-time summary
  python3 tools/token_usage.py --tail 20  # last 20 calls
"""

import json
import sys
import os
from collections import defaultdict
from datetime import datetime, timezone, date

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
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return entries


def fmt_num(n):
    return f"{n:,}"


def print_summary(entries, label):
    if not entries:
        print(f"No entries for: {label}")
        return

    total_input = sum(e.get("input_tokens", 0) for e in entries)
    total_output = sum(e.get("output_tokens", 0) for e in entries)
    total_tokens = total_input + total_output
    calls = len(entries)

    by_model = defaultdict(lambda: {"calls": 0, "input": 0, "output": 0})
    for e in entries:
        m = e.get("model", "unknown")
        by_model[m]["calls"] += 1
        by_model[m]["input"] += e.get("input_tokens", 0)
        by_model[m]["output"] += e.get("output_tokens", 0)

    print(f"\n{'='*50}")
    print(f"  Token Usage — {label}")
    print(f"{'='*50}")
    print(f"  LLM calls   : {fmt_num(calls)}")
    print(f"  Input tokens: {fmt_num(total_input)}")
    print(f"  Output tokens:{fmt_num(total_output)}")
    print(f"  Total tokens: {fmt_num(total_tokens)}")
    if calls > 0:
        print(f"  Avg per call: {fmt_num(total_tokens // calls)} tokens")
    print()
    print("  By model:")
    for model, stats in sorted(by_model.items()):
        total = stats["input"] + stats["output"]
        print(f"    {model}")
        print(f"      calls={fmt_num(stats['calls'])}  in={fmt_num(stats['input'])}  out={fmt_num(stats['output'])}  total={fmt_num(total)}")
    print()


def print_tail(entries, n):
    tail = entries[-n:]
    print(f"\nLast {len(tail)} calls:\n")
    print(f"  {'Timestamp':<25} {'Model':<20} {'In':>8} {'Out':>8} {'Total':>8}")
    print(f"  {'-'*25} {'-'*20} {'-'*8} {'-'*8} {'-'*8}")
    for e in tail:
        ts = e.get("ts", "?")[:19].replace("T", " ")
        model = e.get("model", "?")[:20]
        inp = e.get("input_tokens", 0)
        out = e.get("output_tokens", 0)
        print(f"  {ts:<25} {model:<20} {inp:>8,} {out:>8,} {inp+out:>8,}")
    print()


def main():
    args = sys.argv[1:]
    entries = load_entries()

    if "--tail" in args:
        idx = args.index("--tail")
        n = int(args[idx + 1]) if idx + 1 < len(args) else 20
        print_tail(entries, n)
        return

    if "--all" in args:
        print_summary(entries, "All Time")
        return

    # Default: today
    today = date.today().isoformat()
    today_entries = [e for e in entries if e.get("ts", "").startswith(today)]
    print_summary(today_entries, f"Today ({today})")
    print_summary(entries, "All Time")


if __name__ == "__main__":
    main()
