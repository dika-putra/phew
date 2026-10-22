# Progress

Resume here: read this file, then the plan named in "Current plan", then continue at "Next step".

Current plan: docs/superpowers/plans/2026-10-22-m5-tools.md
Branch: m5-tools
Next step: Final review of m5-tools, then M6 plan

## Carry into M5 (deferred from the M2, M3 and M4 reviews)

- TOCTOU between `PathGuard.check` and `removeItem` (same-user race).
- Nested custom targets are counted twice; cleaning both gives a `missingParent` failure.
- `CleanPlan.needsAdmin` is ignored by the CLI and the app. Handle it in M5 with the admin targets.
- `git ls-files` gets every candidate path as an argument (ARG_MAX on huge Laravel views folders; fails safe).
- Rust `target` is deleted directly; spec says `cargo clean` first (same result).
- The prune list also skips `bin obj deps _build .build .gradle .terraform` beyond spec section 7.
- App: refresh is not blocked during a clean (numbers only); a notification click mid-clean moves to Home.
- App: alert text says "about Zero KB" when nothing is reclaimable; ConfirmView heading "Skipped, in use" also covers unreadable items.
- App: `CLIInstaller` replaces any symlink at `~/.local/bin/phew`, also one pointing at a dev build; `SMAppService` `.requiresApproval` shows no message; Home shows a spinner for "No scan yet".
- Dev server check: the Gradle daemon's cwd is `~/.gradle/daemon`, so it never matches a project.

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
| 2026-10-21 | M4 | Task 3: low space alert state | Add low space alert state |  |
| 2026-10-21 | M4 | Task 4: dev process check | Mark projects with a running dev process as in use |  |
| 2026-10-21 | M4 | Task 5: app target, Home | Add menu bar app with Home | make app; PHEW_SNAPSHOT renders screens; popover click needs user check |
| 2026-10-21 | M4 | Task 6: group view, clean flow | Add group view and clean flow | dev server check narrowed (MCP servers gave false in-use); popover clean needs user check |
| 2026-10-21 | M4 | Task 7: settings, About, alert | Add settings, About and low space alert | interactive checks moved to Task 8 with the user |
| 2026-10-22 | M4 | Task 8: milestone check | Re-anchor the popover after resizing and share one checkbox style | user checked the app; UI changes from feedback: checkbox-only cleaning, Quick clean, Extra folders, folder icon, NSPopover |
| 2026-10-22 | M4 | Final review fixes | Fix M4 review findings | 6 Important fixed; minors in Carry into M5 |
| 2026-10-22 | M4 | Fix after review | Use a plain AppKit entry point | empty "Phew Settings" window came from the placeholder SwiftUI Settings scene |
| 2026-10-22 | M4 | UI fixes after review | Give the popover a solid background | AppKit entry point, no initial focus, appearance on popover, solid background |
| 2026-10-22 | M5 | Task 0: plan | Add M5 plan | m4-menubar merged to main |
| 2026-10-22 | M5 | Task 1: removal kinds | Add command removal to the executor |  |
| 2026-10-22 | M5 | Task 2: pins | Find pinned SDK versions in projects |  |
| 2026-10-22 | M5 | Task 3: package caches | Add npm, pnpm, Go and Cargo caches | login shell for tool commands |
| 2026-10-22 | M5 | Task 4: Docker | Add Docker build cache and images | Docker off -> info with Docker.raw allocated size |
| 2026-10-22 | M5 | Task 5: simulators, runtimes, dyld | Add simulators, runtimes and dyld cache | synthetic simctl fixtures; admin via osascript (app) and sudo (CLI) |
| 2026-10-22 | M5 | Task 6: version managers | Add fvm, nvm and rustup versions |  |
| 2026-10-22 | M5 | Task 7: wiring and minors | Show tool items in the CLI and the app | phew versions; Docker off row with Start Docker; carried M4 minors fixed |
| 2026-10-22 | M5 | Task 8 fix: version in use | Treat a version as in use when a process has it on PATH | nvm use in a terminal now blocks removing that version |
| 2026-10-22 | M5 | Task 8: milestone check | Read the fvm global next to its versions folder | user checked Versions and Start Docker; nvm use detection added |
