# Progress

Resume here: read this file, then the plan named in "Current plan", then continue at "Next step".

Current plan: docs/superpowers/plans/2026-10-21-m4-menubar.md
Branch: m4-menubar
Next step: Task 3, Step 1 (M4)

## Carry into M4 (deferred from the M2 and M3 reviews)

- TOCTOU between `PathGuard.check` and `removeItem` (same-user race). Remove relative to an opened parent handle if it matters.
- Nested custom targets are counted twice; cleaning both gives a `missingParent` failure.
- `CleanPlan.needsAdmin` is ignored by the CLI. Handle it before M5 adds admin targets.
- `git ls-files` gets every candidate path as an argument; a huge Laravel views folder can exceed ARG_MAX (fails safe as "Couldn't check git status").
- Rust `target` is deleted directly; spec says `cargo clean` first (same result).
- No running-process check for project artifacts (`next dev`, `vite`, `flutter run`). Add in M4.
- The prune list also skips `bin obj deps _build .build .gradle .terraform`, beyond spec section 7; projects inside such folders are not found.
- UI: monorepos produce many tiny items (8 KB `.turbo`); group or hide small ones in M4.

## Log

| Date | Milestone | Task | Commit | Notes |
|---|---|---|---|---|
| 2026-10-21 | M1 | Task 0: progress log | Add M1 plan and progress log | Execution: native. Repo moved to ~/Documents/Projects/phew |
| 2026-10-21 | M1 | Task 1: skeleton, phew --version | Add package skeleton and phew --version |  |
| 2026-10-21 | M1 | Task 2: Shell | Add Shell |  |
| 2026-10-21 | M1 | Task 3: DiskSize | Add allocated-size DiskSize | Mounted-volume skip not unit tested, verify in M2 |
| 2026-10-21 | M1 | Task 4: PathGuard | Add PathGuard |  |
| 2026-10-21 | M1 | Task 5: Config | Add shared config |  |
| 2026-10-21 | M1 | Task 6: catalog, phew list | Add built-in catalog and phew list | editors split per editor; some bundle ids unverified (see code comments) |
| 2026-10-21 | M1 | Task 7: milestone check | Finish M1 | release build has no warnings; 34 tests pass; final review pending |
| 2026-10-21 | M1 | Final review fixes | Fix review findings in PathGuard and config | 5 Important fixed; 5 minors deferred to M2 (see M2 plan) |
| 2026-10-21 | M2 | Task 0: plan | Add M2 plan | m1-core merged to main |
| 2026-10-21 | M2 | Task 1: hardening | Harden Shell, DiskSize and PathGuard | M1 review minors done |
| 2026-10-21 | M2 | Task 2: RunningCheck | Add RunningCheck | proc entries support Name=pattern |
| 2026-10-21 | M2 | Task 3: Item, TargetScanner | Add Scanner | named TargetScanner (Foundation.Scanner clash) |
| 2026-10-21 | M2 | Task 4: Planner | Add Planner |  |
| 2026-10-21 | M2 | Task 5: Executor, Receipt | Add Executor and Receipt | one PathGuard per target |
| 2026-10-21 | M2 | Task 6: phew scan | Add phew scan | real scan 25.58 GB in 15 s |
| 2026-10-21 | M2 | Task 7: phew clean | Add phew clean | verified on ~/.phew-m2-test; config restored |
| 2026-10-21 | M2 | Task 8: milestone check | Finish M2 | size parity with du: all 18 items ok; 74 tests |
| 2026-10-21 | M2 | Final review fixes | Fix M2 review findings | 4 Important fixed; 5 minors deferred (see Carry into M3) |
| 2026-10-21 | M3 | Task 0: plan | Add M3 plan | m2-clean merged to main |
| 2026-10-21 | M3 | Task 1: M2 leftovers | Count hard links once per item |  |
| 2026-10-21 | M3 | Task 2: project rules | Add project rules |  |
| 2026-10-21 | M3 | Task 3: ProjectWalker | Add ProjectWalker |  |
| 2026-10-21 | M3 | Task 4: GitSafety | Add GitSafety |  |
| 2026-10-21 | M3 | Task 5: ProjectScanner | Add ProjectScanner |  |
| 2026-10-21 | M3 | Task 6: CLI | Add project scan to the CLI | phew config --add-root/--remove-root; projects ids in clean |
| 2026-10-21 | M3 | Task 7: milestone check | Finish M3 | real scan: 5 projects, 9.87 GB in 20 s; roots kept |
| 2026-10-21 | M3 | Final review fixes | Fix M3 review findings | 1 Critical + 3 Important fixed; minors in Carry into M4 |
| 2026-10-21 | M4 | Task 0: plan | Add M4 plan | m3-projects merged to main |
| 2026-10-21 | M4 | Task 1: scan cache | Add scan cache |  |
| 2026-10-21 | M4 | Task 2: summary | Add scan summary |  |
