"""Summarise a phone `devicectl --console` log run with -AudioLog 1.

Timestamp-agnostic: counts every `[audio] req <what> slot <n> -> <reason>` line (request, slot, reason),
every `[audio] chirp slot ...` line (post-guard plays), the last `[audio] state` line, and simulated seconds
from the `[melon] perf:` step counts (steps/60) so a stalled run is obvious.
Chirp requests carry the caller tag since 2026-11-05 (`chirp:happy@idle`, `@greet`, `@wave`, `@cafe`, `@park`, `@guest`, `@group`, `@window`, `@other` = untagged
caller): a second table groups the chirp requests by tag (and by slot) with their played / dropped counts; an older log with no tags is all "(untagged log)".
Usage: python3 -I scripts/audiolog_summary.py <console.log>
"""
import collections
import re
import sys

path = sys.argv[1]
lines = open(path, errors="replace").read().splitlines()
req = collections.Counter()
by_what = collections.Counter()
played = collections.Counter()
chirp_slots = collections.Counter()
states = []
vol_sum = collections.Counter(); vol_n = collections.Counter()
tag_total = collections.Counter(); tag_played = collections.Counter(); tag_slot = collections.Counter(); tag_why = collections.Counter()
steps = 0
perf_lines = 0
for l in lines:
    m = re.search(r"\[audio\] req (\S+) slot (\S+) -> (.*)$", l)
    if m:
        what, slot, why = m.groups()
        reason = why.split(" ")[0] if why.startswith(("level", "scene", "PLAYED")) else why          # ("PLAYED v=0.53": the effective volume rides after the token)
        req[(what, reason)] += 1
        by_what[what] += 1
        if why.startswith("PLAYED"):
            played[what] += 1
            vm = re.search(r"v=([\d.]+)", why)
            if vm: vol_sum[what] += float(vm.group(1)); vol_n[what] += 1
        if what.startswith("chirp:"):
            tag = what.split("@", 1)[1] if "@" in what else "(untagged log)"
            tag_total[tag] += 1; tag_slot[(tag, slot)] += 1
            if why.startswith("PLAYED"): tag_played[tag] += 1
            else: tag_why[(tag, reason)] += 1
        continue
    m = re.search(r"\[audio\] chirp slot (\d+)", l)
    if m:
        chirp_slots[m.group(1)] += 1
        continue
    if "[audio] state" in l:
        states.append(l[l.index("[audio] state"):])
        continue
    m = re.search(r"(\d+) steps\), skin", l)
    if m:
        steps += int(m.group(1))
        perf_lines += 1

print(f"lines {len(lines)}; perf lines {perf_lines}; simulated {steps / 60:.1f} s")
print(f"post-guard chirp lines by slot: {dict(chirp_slots)} (total {sum(chirp_slots.values())})")
print("requests by kind (played / total):")
for what, n in by_what.most_common():
    vol = f"  mean v={vol_sum[what] / vol_n[what]:.2f}" if vol_n[what] else ""
    print(f"  {what:24s} {played[what]:4d} / {n}{vol}")
if tag_total:
    print("chirp requests by caller tag (played / total; by slot; drop reasons):")
    for tag, n in tag_total.most_common():
        slots = {sl: c for (t, sl), c in sorted(tag_slot.items()) if t == tag}
        drops = {r: c for (t, r), c in tag_why.items() if t == tag}
        print(f"  {tag:16s} {tag_played[tag]:4d} / {n:<4d} slots {slots} drops {drops}")
print("drop-reason histogram (request, reason: count):")
for (what, why), n in sorted(req.items(), key=lambda kv: -kv[1]):
    print(f"  {what:24s} {why:28s} {n}")
if states:
    print("first state:", states[0])
    print("last state: ", states[-1])
