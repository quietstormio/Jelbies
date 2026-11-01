---
name: cleanup
description: Reclaim disk space safely: dry-run list of build caches, agent simulators, stale worktrees and scratch copies; delete only with --apply
---

# /cleanup

Reclaims disk space without touching anything that matters.

1. Run the dry run from the repo root: `scripts/cleanup-safe.sh` (flags: `--keep-dev-hours N`, `--all-sims`, `--protect NAME`, `--min-free-gb N`). It deletes nothing.
2. Show the user the table (SAFE vs PROTECTED, sizes, total reclaimable).
3. Ask the user before running `scripts/cleanup-safe.sh --apply --yes`, unless they already said "just clean" (then go straight to apply).
4. Never delete PROTECTED items by any other means (no manual `rm`, no `--force`). That covers `~/BobV1_backups`, the repo and `.git`, memory, `~/.config`, `dd_*_dev` newer than the keep window, dirty or unmerged worktrees, `g-int`, Booted or user-named simulators, and scratchpad captures/boards.
5. After apply, report the freed GB (the script prints `df` before/after). If it exits non-zero (still under `--min-free-gb`), show the "biggest remaining" list and ask what else to remove.

Note: anything written in the last 30 minutes is kept as a possible live build; rerun later if the sweep is mid-round.
