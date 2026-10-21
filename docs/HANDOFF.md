---
name: project-handoff-2026-10-20
description: "Work was paused on 2026-10-20 for the user's Mac upgrade, with 7 work-in-progress branches unmerged. Read this first in the next session."
metadata:
  node_type: memory
  type: project
  originSessionId: 6a40096b-092a-48d0-8cbe-4e00ccea7702
  modified: 2026-10-21T02:12:42.696Z
---

The user paused work so they could upgrade their Mac. Everything is committed LOCALLY. The `git push` of the wip branches was blocked by the auto-mode classifier, so ask the user to push them or allow the push. The pushed checkpoint is circuit-v1 @ 361c185 (checkpoint 7c). main is still at checkpoint 6.

## Branches (all based on 361c185)
| branch | location | state |
|---|---|---|
| wip/liveliness @ 8444ff6 | main tree (/Users/dmarshall94/Desktop/BobV1, now checked out on this branch) | expressions + brows + blush, mid-walk flourishes, reaction bus, roll/sigh/hmph. Builds. Most tests were green. Still to do: diagnose AnticsTests `testThreeJelliesNeverRepeat` (230 same-moment repeats, probably reactions/copycat); re-run BaseBodyLock (the blush moved to x0.315, y0.69); regenerate the captures; device build |
| worktree-agent-a7c11d13574b7083b @ 25e0275 | .claude/worktrees/agent-a7c11d… | characters: Pip spines, Moss daisy (+ on-hat), Lavender as 4th Jelbie with wings + flap-hop, compat rules. Builds. FeatureTests mostly green; regressions and the perf test not run. Caveat: backpack + any neck item folds the wings |
| worktree-agent-a73e243a0334088fb @ f03624e | .claude/worktrees/agent-a73e… | soccer: the ball + mini goal replace the football. The worker was STOPPED mid-debug (kick/shot tests, dribble nudge, open-floor search). Untested |
| worktree-agent-a5343a0f13b503f27 @ d2814f3 | .claude/worktrees/agent-a534… | curvy courses Puddle/Ripple/Splash/Wave, picker, camera. Mostly green. 3 failing tests are listed in that commit's report: puddle golden start-z, Wave camera halfWidth, seed-19 timeout |
| worktree-agent-a1a9e1b4155a8d30d @ 29a412b | .claude/worktrees/agent-a1a9… | on-device AI: FoundationModels natural voice commands (Tier A) + rule parser fallback (Tier B), EventLog, diary, thought lines. App builds; AI tests not run |
| worktree-agent-a42ee91e25f7f3a68 @ 59cf767 | .claude/worktrees/agent-a42e… | Ears on (SoundAnalysis + DSP fallback). Detector/DSP done and tested. Still to do: EarsListener, AudioHub hooks, HUD/settings, brain hooks, mic-usage string |
| worktree-agent-a4e1d9bf7bb887f84 @ 997f404 | .claude/worktrees/agent-a4e1… | Apple extras: App Intents/Siri, Lock Screen + StandBy widgets, Live Activities (race/nap/pep). NOT YET COMPILED. Still to do: JelbiesIntents.swift, snippet view, settings panel, GameScreen hooks, tests. The app display name is "Bob", so Siri phrases will read "in Bob" |

## Next session plan
1. Ask the user to push, or allow pushing, the wip branches.
2. Finish each branch with a worker (Fable is OK; the user asked for Fable subagents for speed). Then merge in this order: liveliness → characters → soccer → courses → AI → ears → apple extras. Run the full regression suite after each merge.
3. After the merges: rename the in-game text Jellies→Jelbies ([[project-naming-one-size]]). Keep the "Jelly Circuit" and "Jelly Show" names.
4. Then build the Jelly Show (designed: canvas https://claude.ai/artifact/SNrMLuH93KdAP6ofr1bEGg, jelly-jars Condition screen; [[project-beauty-contest]]).

## Where things are
- Scratchpad: the /tmp scratchpad is wiped on reboot. It was copied to ~/BobV1_backups/scratchpad_2026-10-20/ (26 GB). Key items:
  - art exports: food_art/export, wear_art/export, char_art/export (+ compat.json)
  - plans: soccer_plan.md, fixC_diag.md, contest_research*.md, music_pick/picks.json
  - captures
- The phone has the fix-round-B build (pre-7c). The latest installable signed app is lost with /tmp; rebuild before installing.
- Old stale worktrees (agent-a0bab…, a0ebcb…, a1811…, a52d4…, a5839…, a8881…, a89c1…, ab713…, ae999…) are from earlier checkpoints and can be cleaned up only after the user OKs it.
