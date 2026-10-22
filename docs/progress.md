# Progress

Resume here: read this file, then the plan named in "Current plan", then continue at "Next step".

Current plan: docs/superpowers/plans/2026-10-22-m6-release.md
Branch: m6-release
Next step: Task 4, Step 1 (M6)

## M5.5 decisions (UI review, 2026-10-22)

1. Right-click status item menu: Open, Refresh, Settings…, Quit (⌘Q); Quit button in Settings.
2. Settings stays in the popover; ⌘, opens it.
3. Return = Clean except when the plan has data-loss items; Esc = Cancel.
4. Item rows on two lines, size right-aligned.
5. Items sorted by size inside a group.
6. Tri-state checkbox in each group header.
7. Hover highlight on rows.
8. Unticked preselected items are kept ("Kept items" in Settings); Quick clean leaves them out.
9. Badge text contrast at least 4.5:1 (darker light-mode shades).
10. Icon buttons have 28x28 pt hit areas.
11. Information text at 11 pt (subheadline); badges 10 pt.
12. Spacing scale 4/8/12/16/24.
13. Popover resize animation back on (revert if it jumps).
14. Scan stage text while scanning.
15. "Last clean: X freed, Y ago" on Home.
16. English only.
17. Free space text next to the menu bar icon: deferred.
18. Logo concept I (prompt with a breathing cursor): app icon #1E2229 with #7CF5C8 lines.
19. Menu bar icon: template, chevron and curl only (replaces SF Symbol wind).
20. README banner 1280x320, light and dark: icon, "phew" in monospace, one-line tagline.
21. README Uninstall section (written in M6 Task 2).

## Carry into M6 (deferred from the M2 to M5 reviews)

- TOCTOU between `PathGuard.check` and `removeItem` (same-user race).
- Nested custom targets are counted twice; cleaning both gives a `missingParent` failure.
- `git ls-files` gets every candidate path as an argument (ARG_MAX on huge Laravel views folders; fails safe).
- Rust `target` is deleted directly; spec says `cargo clean` first (same result).
- The prune list also skips `bin obj deps _build .build .gradle .terraform` beyond spec section 7.
- Dev server check: the Gradle daemon's cwd is `~/.gradle/daemon`, so it never matches a project.
- Docker: a `docker` CLI without Docker Desktop (colima, OrbStack stopped) shows "off · 0 B" and Start Docker fails silently; `docker info` can hold the tool scan up to 60 s.
- nvm from Homebrew, or nvm with no default alias, locks every version; `NVM_DIR`, `RUSTUP_HOME`, `CARGO_HOME` are read from the GUI environment only.
- "Used by" misses `.nvmrc` aliases (`lts/*`) and rust pins like `1.79` against `1.79.0-…`.
- The osascript admin prompt is killed after 600 s.

- README (M6 Task 2): open with `<picture>` using `docs/banner-dark.png` and `docs/banner-light.png` (2560x640, show at width 640).
- README "Uninstall": quit Phew, turn off Launch at login in Settings, delete `/Applications/Phew.app`, `rm ~/.local/bin/phew` (if installed from Settings), `rm -rf ~/.config/phew ~/Library/Caches/com.dikaputra.phew`, `defaults delete com.dikaputra.phew`.

- Scan stage label: a late stage update from one scan can show briefly during the next (cosmetic; fix with a scan counter if seen).
- Clearing a group checkbox keeps all its preselected items out of Quick clean (by design, pinned by a test); watch for user confusion.

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
| 2026-10-22 | M5 | Final review fixes | Fix M5 review findings | 1 Critical + 4 Important fixed; minors in Carry into M6 |
| 2026-10-22 | M6 | Task 0: plan | Add M6 plan | m5-tools merged to main |
| 2026-10-22 | M5.5 | Task 0: plan | Add M5.5 plan | UI review decisions recorded; logo concept I chosen |
| 2026-10-22 | M5.5 | Task 1: model | Add kept items, last clean, scan stage and group selection | kept items in UserDefaults (app only); locked items no longer selectable via project checkbox |
| 2026-10-22 | M5.5 | Task 2: views | Follow HIG sizes and add two-line rows | snapshots checked; Home tier badges stack when they don't fit one line; checkbox is a 28 pt target too |
| 2026-10-22 | M5.5 | Task 3: logo | Add Phew logo | user ok; make icons regenerates icns and banners |
| 2026-10-22 | M5.5 | Task 4: AppKit + user check | Add status item menu and shortcuts | user checked all 14 points ok; popover animation kept on; ⌘Q moved to the popover root |
| 2026-10-22 | M5.5 | Task 5: spec, carry notes | Describe M5.5 UI changes in the spec | README banner and Uninstall carried into M6 |
| 2026-10-22 | M5.5 | Final review fixes | Select items that become ready on refresh | 0 Critical, 1 Important fixed with test; minors tested or carried |
| 2026-10-22 | M6 | Merge main | Merge branch 'main' into m6-release | brings M5.5 (UI polish, logo) into the M6 branch |
| 2026-10-22 | M6 | Task 1: CLI help, sudo, failure text | Polish CLI help and step failure text | PhewCLITests added; sudo -v first; failure "<title>: <last stderr line>"; root help shows scan/clean/config |
| 2026-10-22 | M6 | Task 2: README, NOTICE | Add README and NOTICE | screenshots skipped ("Screenshots coming"); README commands run: scan, clean --dry-run, clean (asks, needs a terminal), list, versions, config. HOME= does not redirect phew (getpwuid home): a test root landed in the real config and was removed |
| 2026-10-22 | M6 | Task 3: release build | Add make release | dist/Phew-0.1.0.zip 3.4 MB; lipo x86_64 arm64 for both; adhoc; shasum -c OK; unzip + xattr + phew --version direct and through a link OK |
| 2026-10-22 | M6 | Task 3: dmg | Add a dmg to make release | user asked for dmg and zip; Phew-0.1.0.dmg 3.7 MB with an Applications link; hdiutil verify OK; install from the mounted dmg OK |
