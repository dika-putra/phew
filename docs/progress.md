# Progress

Resume here: read this file, then the plan named in "Current plan", then continue at "Next step".

Current plan: docs/superpowers/plans/2026-10-21-m2-clean.md
Branch: m2-clean
Next step: Task 1, Step 1 (M2)

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

## Carry into M2 (deferred from the M1 review)

- PathGuard checks against the union of all roots. Build one guard per target in M2.
- Custom paths `~/Library`, `~/Documents`, `~/Desktop`, `~/.ssh` are accepted. Consider refusing them.
- DiskSize returns 0 with an empty `unreadable` list when the root itself cannot be read (TCC). Report it as unreadable.
- Shell searches empty or relative `PATH` entries. Skip entries that do not start with `/`.
- Shell has no timeout. Add one before M2 runs `xcrun` and `docker`.
| 2026-10-21 | M2 | Task 0: plan | Add M2 plan | m1-core merged to main |
