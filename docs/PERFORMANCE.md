# Performance notes (2026-10-31 / 11-01 sweep)

Acceptance bar (user): **a 20-minute session on an iPhone 17 Pro Max stays in the `nominal` thermal state**, at 60 fps, with no visible hitches. "If the app heats the phone, what's the point of the game."

## Rules that came out of the sweep

1. **No Liquid Glass / materials / blur over the game view.** iOS 26 `.glassEffect` (and any material or blur) drawn over the live Metal view makes the compositor re-sample the game every frame on the same GPU. Measured on the phone with the calibration draw (`-GpuCal 1`): during the surges our fixed-cost calibration kernels slowed **12×** (ALU 0.56 → 6.9 ms, memory 0.97 → 8.4 ms), queue wait reached 25 ms, and the game frame went 10 → 41 ms with nothing of ours changing. With opaque pills (`-NoMaterials`, now the default) the surges vanished: 29 windows across room/town/park/roster, GPU max 12.7 ms. HUD elements over the game use opaque cream fills and shadows of radius ≤ 6.
2. **Don't render under a covering screen.** The game kept drawing at 60 fps under "Where to?", the shop, the bag and the pause scrim. The Metal view pauses (or drops to a few fps) while a screen covers it.
3. **Thermal-first governor.** Sustained budget ≈ GPU 6 ms / CPU 5 ms per frame, default render rung 880 px wide + MetalFX, climb only when `nominal` with headroom for 30 s, step down on `fair` with a 60 s hold; 30 fps, halved substeps and no re-skin for still bodies after 2 s idle; the same in every scene.
4. **Body shader:** the same matte maths compiled as function-constant-specialised pipelines per species (bit-identical, ~4× cheaper on the Mac, modest on A19); the fibre noise comes from a 64³ lattice texture (`-FibreLUT 1`, default; `-FibreLUT 0` = exact ALU noise) — the fibre was 36 of the 46 noise evaluations per pixel.
5. **Route planner:** per-search and per-step probe budgets, nearest-corner stop, failure back-off; `pickAutonomous` plan budget 12 → 2. Before: 2,300–14,500 `intrusion` probes per call, 20–60 ms stalls, up to 12 plans in one step in the park.
6. **Frame pacing:** draw gaps snap to whole display intervals (one 1/60 step per 60 Hz frame); 120 Hz only when both CPU and GPU have headroom, never in Low Power / thermal ≥ fair.
7. **Memory:** studio-only render targets are not allocated in the game path (−80 to −148 MB).
8. **Park visitors** solve with 6 substeps; menu timelines are throttled.

## How to measure on the phone

- Instruments cannot attach while the phone's iOS is newer than Xcode (iOS 27.2 vs Xcode 27.1 → "Timed out waiting for device to boot").
- The game has its own meter: launch once with `-PerfLog 1` (persists; `-PerfLog 0` clears). Every 5 s it appends a JSON line to `Documents/perf_log.jsonl`: frame intervals (mean/p50/p95/p99/max), CPU per stage (brain, sim, skin, feature, wear, encode, gpu_wait), GPU ms per frame, scene, render scale, thermal, Low Power, and a `ctx` string (room-cache action shares, camera moving %, room px shaded, focus, overlay tags, `cal[…]` with `-GpuCal 1`, `qwait[…]`, thermal transitions, gpuMem). Pull it with `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier io.mgsllc.BobV1 --source Documents/perf_log.jsonl --destination …`.
- Once-a-second `[melon] perf / env / parts / hop parts / bodies / planner` lines: `xcrun devicectl device process launch --console --terminate-existing --device <udid> io.mgsllc.BobV1 -- <app args>` (the `--` is needed when an app arg could parse as a devicectl flag).
- A/B flags: `-NoMaterials 0|1`, `-GpuCal 1`, `-MetalFX 0|1`, `-FibreLUT 0..3`, `-PerfEncoders 1`, `-ImportSave 1`, `-NewGame …`.
- `-PerfPasses 1` double-counts (command-buffer spans overlap); use `-PerfEncoders 1` or ablation.

## Numbers (iPhone 17 Pro Max, 3 Jelmiko in the room)

| Build | interval mean | GPU mean | notes |
|---|---|---|---|
| r1042 (before) | 19–20 ms (36–48 % late) | 11.8 ms at 2×, 18 at 2.5× | Low Power on: 29 fps; brain stalls p95 18–22 ms |
| r1045 (spec shader + memory) | 21 ms | 10.2 ms | planner stalls still p95 24–44 |
| r1048 (planner, pacing, MetalFX, feet) | 16.7 ms steady; surges to 45 ms | 9–10 ms steady | surges = glass contention |
| r1049 `-NoMaterials 1` | 16.7–21 ms, no surges | 8–12 ms | thermal still `fair` from the long session |

Disk hygiene for agent rounds: see `docs/HANDOFF.md` (Disk hygiene) and `scripts/cleanup-safe.sh`.
