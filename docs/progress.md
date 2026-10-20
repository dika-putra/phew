# Progress

Resume here: read this file, then the plan named in "Current plan", then continue at "Next step".

Current plan: docs/superpowers/plans/2026-10-21-m2-clean.md
Branch: m2-clean
Next step: Final review of m2-clean, then M3 plan

## Carry into M2 (deferred from the M1 review)

Done in M2 Task 1, except one guard per target (M2 Task 5).

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
