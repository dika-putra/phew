# Phew: plan

Design and build plan. Read it fully before writing code. It replaces `clean-code-mac-plan.md` from the `mac-storage-cleaner` repo; the old bash script is kept in `docs/reference/everclean.sh` as the behavior spec for the targets it covers.

## 1. What and why

Phew is a native macOS menu bar app (plus a CLI) that frees disk space taken by developer files that can be rebuilt or downloaded again: build output, package caches, SDKs and toolchain versions, simulators and emulators, Docker data.

The author built `everclean.sh` for their own Mac (Flutter, iOS, Android, Node, Rust, Go, Docker). Phew makes that useful for any developer: more stacks (PHP, Laravel, WordPress, Python, Ruby, Java, .NET and others), a menu bar UI, and user-defined paths for stacks that are not covered.

Success: a developer opens the menu bar, sees free space and what can be reclaimed per category, cleans one item or a selection after a confirmation, and the reported freed space is the real measured change.

## 2. Decisions

Made by the user:
- Name: Phew (display name). Repo `dika-putra/phew` on GitHub, private for now, open source (MIT) later. CLI binary `phew`.
- The menu bar popover is the main UI. Cleaning happens inside the popover, always after a confirmation.
- Items are picked with checkboxes (per item, and per project in the Projects group) and cleaned with one "Clean selected" button. No per-item Clean buttons (changed during M4: too many buttons). Each row and project has a small folder icon that shows it in Finder.
- Background size scan every 2 hours, plus a Refresh button for a manual scan.
- Full Disk Access (FDA) is supported but optional. Items that need FDA carry an FDA badge. When FDA is not granted, the item shows a button that opens the FDA pane in System Settings.
- Users can add their own paths (custom targets, shown in the app as "Extra folders"). The built-in catalog covers commonly used stacks only.
- No scheduled auto-clean.
- No Apple Developer ID, no notarization. Ad-hoc signature. Users run `xattr -cr` or build from source.

Carried over from the old plan:
- New project, not a fork. PureMac and mac-cleaner-cli are MIT. Keep attribution in `NOTICE` for anything adapted (the PureMac cache path list is the main one).
- Swift 6 with strict concurrency, minimum macOS 14. Only dependency: swift-argument-parser (CLI). Tests: Swift Testing.

Builder calls (made while writing this plan, change if wrong):
- Bundle id `com.dikaputra.phew`.
- Deletes are permanent (`FileManager.removeItem`), not to the Trash, because the Trash does not free space.
- The background scan only measures, it never deletes.
- Docker cleanup does not stop running containers (the old script did). `docker system prune -a -f` only removes unused data. Volumes are never touched.
- Config is one JSON file shared by the CLI and the app: `~/.config/phew/config.json`.
- Launch at login via `SMAppService.mainApp`, off by default, toggle in settings.
- `macos.caches` is "Other caches": `~/Library/Caches` minus every folder another target owns and minus Phew's own cache. Not preselected (`optIn`).
- Projects inside projects: rules are evaluated on every folder, matching does not stop the walk. Artifacts are grouped under the outermost project (a Flutter app shows its `ios/Pods` and `android/app/build`). Stacked markers (Laravel plus Node in one folder) apply all matching rules.
- Command targets measure a known path when one exists (`brew --cache`, `pnpm store path`, `go env GOMODCACHE`). Docker uses the `docker system df` delta. Only when neither exists, the volume free-space delta is used and the receipt labels it "approximate".
- Admin deletes run the `phew` CLI bundled inside the app as root (`osascript` with administrator privileges, fixed arguments such as `phew admin-delete dyld <runtime build>`). PathGuard and the enumeration delete run inside the root process. No shell `rm` string is built in the app.
- Project roots that are symlinks are resolved once when saved in the config; the resolved real path is the allowlisted root, and it may be on another volume. Inside the walk, symlinks are never followed.
- Item ids: `<target>` for catalog and custom targets, `<target>:<key>` for sub-items (`projects:<absolute path>/<artifact>`, `nvm:20.11.0`, `ios.runtimes:<uuid>`). `phew clean` accepts both forms.

## 3. Non-goals and anti-goals

Non-goals: app uninstaller, duplicate finder, large and old files, photos, Mail, Time Machine snapshots, RAM or "speed up" features, treemap, scheduler, auto-update. PureMac already covers the general cleaner space.

Anti-goals (a failure even if it works):
- Reporting freed space that was not measured.
- Deleting anything a user created that cannot be recreated, without a separate warning.
- Deleting a folder inside a project only because of its name (`build`, `dist`, `vendor`, `public`).
- Fear-based UI ("47 GB of junk!"). Show neutral numbers.
- Telemetry or network calls.

## 4. Tiers

Each item has one tier. It tells the user what it costs to get the space back.

| Tier | Meaning | Examples | Default selection |
|---|---|---|---|
| `regenerates` | Rebuilt from source, no network | DerivedData, `build/`, `.dart_tool`, `__pycache__`, editor caches | selectable in bulk |
| `redownload` | Downloaded again, needs network and time | `node_modules`, `vendor/`, Gradle cache, npm cache, fvm/nvm versions, simulator runtimes | selectable in bulk; show size as "download ~X" |
| `dataLoss` | Holds user data that cannot be recreated | AVDs, Xcode Archives, Docker images built locally | never preselected; confirmation shows a red warning |

Flags on an item, independent of tier:
- `heavy`: large and slow to get back (Android SDK, runtimes). Never preselected.
- `needsAdmin`: root-owned (simulator dyld cache). Separate confirmation, admin prompt.
- `needsFDA`: path is protected by TCC. FDA badge.
- `optIn`: never preselected, even if the tier would allow it (Maven, NuGet, Other caches).
- `skipIfRunning`: list of bundle ids or process patterns. If one is running, the item is not cleaned. The row shows an "in use" badge with the app name, and the Clean flow tells the user why (section 11).

Preselection rule: an item is preselected only if it is `regenerates` or `redownload`, not `heavy`, not `needsAdmin`, not `optIn`, and (for project items) the project is dormant. Dormant means no file in the project changed in the last `dormantDays` (default 14) days, measured on the project folder excluding the artifact folders.

## 5. Architecture

```
phew/
  Package.swift
  Sources/
    PhewCore/      Catalog/ (built-in targets as data) Targets/ (custom kinds) Services/ (Shell, DiskSize, PathGuard, RunningCheck, Privilege, FDA) Clean/ (Plan, Executor, Receipt) Config/
    phew/          CLI (swift-argument-parser)
  Tests/PhewCoreTests/
  App/             SwiftUI menu bar app, Xcode project that depends on the local package
  docs/
  NOTICE
```

Target kinds. Most targets are data. Only a few need code.

1. `PathTarget` (data): id, group, title, tier, flags, paths. Option `contents: true` deletes the children of the path and keeps the folder. Covers almost all global caches.
2. `ProjectRule` (data): markers, artifact folders, tier. Used by the project scanner (section 8).
3. `VersionManager` (code, one protocol, one type per tool): list installed versions with size, find pinned versions in projects, lock active and default, remove one version with the tool's own command. Section 9.
4. Custom targets with real logic (code): simulator runtimes, unavailable simulators, simulator dyld cache, Docker, npm/pnpm/go/cargo where a command is preferred over a folder delete.

Core flow, the same for the CLI and the popover:

`scan` -> `[Item]` -> `plan(selection)` -> `CleanPlan` (items, paths or commands, expected bytes) -> user confirms -> `execute` -> `Receipt`.

`Item`: id, target id, title, path or command, allocated size, `lastUsed`, `usedBy` (projects or pins), tier, flags, state (`ready`, `inUse`, `needsFDA`, `needsAdmin`).

`Receipt`: per item claimed bytes, measured bytes, failures; volume free space before and after.

## 6. Safety rules (hard requirements)

From real bugs in the bash script (section 7):
1. `Receipt` reports measured deltas only. Re-measure each item after deleting it. Never report the selection size as freed.
2. `PathGuard`: a path must be inside an allowlisted root (the built-in catalog roots, configured project roots, custom target paths). Refuse `/`, the home folder itself, `/System`, `/Library` (except the listed `/Library/Developer/CoreSimulator` paths), and any path that resolves outside its root. Do not follow symlinks; delete the link, not its target.
3. Delete children by enumeration including hidden entries. Never a glob like `dir/*`.
4. Sizes are allocated sizes (`totalFileAllocatedSize`), hard links counted once (dedupe by `fileResourceIdentifier`). Do not walk mounted volumes (`/Library/Developer/CoreSimulator/Volumes`).
5. Nothing is deleted without a confirmation. The CLI needs `--yes` to skip it.
6. Processes start with the working directory set to `$HOME`.

New:
7. Project artifacts are deleted only when the project marker matches (section 8) and the artifact folder is ignored by git when the project is a git repo (`git -C <project> check-ignore -q <folder>`). A folder tracked by git is skipped and shown as "tracked by git".
8. Items with `skipIfRunning` are rechecked right before deleting, not only at scan time.
9. Docker volumes are never removed.
10. Custom targets from the config go through `PathGuard` like built-in ones. A custom path cannot be `/`, the home folder, or a parent of the home folder.

## 7. Lessons from the bash script (gotchas)

- The glob `dir/*` skips hidden entries. `~/.dartServer/.analysis-driver` (1.5 GB) and `~/Library/Android/sdk/.downloadIntermediates` were never deleted. Use an enumerator.
- `du` over `/Library/Developer/CoreSimulator/Volumes/iOS_*` counts mounted disk images again (62 GB shown, 27.8 GB real). Real size is `sizeBytes` from `xcrun simctl runtime list -j`.
- A delete that failed silently was reported as "freed 38 GB" while the disk had not changed. Verify by re-measuring.
- `xcrun simctl runtime delete` takes the UUID or the build (for example `22F77`), not `18.5`. It has `--dry-run`. Runtime JSON keys: uuid as key, `build`, `sizeBytes`, `lastUsedAt`, `runtimeIdentifier`, `state`. Simulators per runtime: `xcrun simctl list devices -j`, state `Booted`.
- After a runtime is deleted, CoreSimulator can lag before it marks the simulators unavailable. Retry `xcrun simctl delete unavailable` up to 3 times with 3 seconds between tries.
- Simulator dyld cache: `/Library/Developer/CoreSimulator/Caches/dyld/<macOS build>/com.apple.CoreSimulator.SimRuntime.<id>.<runtime build>`. Owned by root, needs admin.
- Project scan prune list: `node_modules build .dart_tool target dist .next .nuxt .output .svelte-kit .turbo .git vendor .venv venv Pods` plus AI tool folders `.opencode .claude .cursor .windsurf .aider .continue .codeium`.
- Docker: check `docker info` first (Docker Desktop may be off). Build cache only: `docker builder prune -a -f`. Images and containers: `docker system prune -a -f` without `--volumes`. Reclaimable size: `docker system df --format '{{.Reclaimable}}'` (units B, KB, MB, GB, TB).
- npm: `npm cache clean --force` leaves `~/.npm/_npx`, remove it separately. pnpm: `pnpm store prune` removes only unreferenced packages, store path from `pnpm store path`. Go: `go clean -modcache`, path from `go env GOMODCACHE`. Cargo: remove `~/.cargo/registry/cache` and `src`, keep `index`.
- fvm: versions folder from the `Cache directory:` line of `fvm list`. Remove with `fvm remove <version>`. Pins: `.fvmrc` (`{"flutter": "3.24.5"}`) and legacy `.fvm/fvm_config.json` key `flutterSdkVersion`. One project can have both, count it once.
- nvm is a shell function. Run it through `bash -c 'source "$NVM_DIR/nvm.sh"; ...'`. Use `nvm current`, `nvm version default`, `nvm uninstall`. `.nvmrc` matches by version prefix.
- Editors: cache-only subfolders `Cache CachedData CachedExtensionVSIXs "Code Cache" GPUCache DawnGraphiteCache DawnWebGPUCache logs` under `~/Library/Application Support/<editor>`. Never touch extensions or settings.
- A process started inside a deleted folder prints `getcwd` errors. Start in `$HOME`.
- Reference numbers from the author's Mac: free space 5.8 GB to 67 GB after cleaning about 60 GB. Largest: simulator runtimes 27.8 GB, dyld cache 10.4 GB, Gradle 10 GB, npm 8.6 GB, AVD 5 GB, Android SDK 4.6 GB.

Not verified yet, check during the build:
- Docker Desktop stores its VM disk in a sparse `Docker.raw`. Free space on the Mac may update later than the prune. If the measured delta is near zero right after a Docker prune, the receipt says the space is freed inside Docker and the Mac disk catches up later, instead of reporting a failure.
- TCC ties the FDA grant to the code signature. With an ad-hoc signature each new build may lose FDA. Check this; if true, document it in the README.

## 8. Built-in catalog v1

### Path targets

Paths start at `~` unless absolute. Paths marked FDA need FDA (verify each during the build by checking readability without FDA).

| Group | id | Paths | Tier, flags |
|---|---|---|---|
| macOS | macos.caches | `Library/Caches` (contents, minus folders owned by other targets) | regenerates, optIn |
| macOS | macos.logs | `Library/Logs` (contents, minus folders owned by other targets) | regenerates |
| Xcode | xcode.deriveddata | `Library/Developer/Xcode/DerivedData` | regenerates, skip Xcode |
| Xcode | xcode.archives | `Library/Developer/Xcode/Archives` | dataLoss (dSYMs of shipped builds) |
| Xcode | xcode.devicesupport | `Library/Developer/Xcode/{iOS,watchOS,tvOS} DeviceSupport` | redownload, heavy |
| Xcode | xcode.caches | `Library/Caches/com.apple.dt.Xcode`, `Library/Developer/CoreSimulator/Caches` | regenerates |
| Xcode | xcode.previews | `Library/Developer/Xcode/UserData/Previews`, `Library/Developer/XCTestDevices` | regenerates |
| Xcode | swiftpm | `Library/Caches/org.swift.swiftpm` | redownload |
| Xcode | cocoapods | `Library/Caches/CocoaPods` | redownload |
| Android | gradle | `.gradle/caches`, `.gradle/wrapper/dists`, `.gradle/daemon` | redownload, skip Android Studio and GradleDaemon |
| Android | android.systemimages | `Library/Android/sdk/system-images` | redownload, heavy |
| Android | android.avd | `.android/avd` | dataLoss, heavy, skip emulator |
| Flutter | dart.pubcache | `.pub-cache` | redownload |
| Flutter | dart.analysis | `.dartServer` | regenerates |
| Node | yarn | `Library/Caches/Yarn`, `.yarn/berry/cache` | redownload |
| Node | bun | `.bun/install/cache` | redownload |
| Node | browsers | `.cache/puppeteer`, `Library/Caches/ms-playwright` | redownload |
| Node | node-gyp, electron | `Library/Caches/node-gyp`, `Library/Caches/electron`, `Library/Caches/electron-builder` | redownload |
| Python | pip, uv, poetry | `Library/Caches/pip`, `.cache/uv`, `Library/Caches/pypoetry` | redownload |
| Python | conda.pkgs | `{miniconda3,anaconda3,miniforge3}/pkgs` | redownload |
| PHP | composer | `Library/Caches/composer`, `.composer/cache` | redownload |
| Ruby | gem, bundler | `.gem/specs`, `.bundle/cache` | redownload |
| Java | maven | `.m2/repository` | redownload, optIn (may hold local installs) |
| .NET | nuget | `.nuget/packages` | redownload, optIn |
| Go | go.buildcache | `Library/Caches/go-build` | regenerates |
| Homebrew | brew | command `brew cleanup -s` and `Library/Caches/Homebrew` | redownload |
| Editors | editors | cache subfolders of VS Code, Cursor, Windsurf, Devin, Zed; `Library/Caches/JetBrains`, `Library/Logs/JetBrains` | regenerates, skip that editor |
| Containers | orbstack | `.orbstack/log`, `Library/Caches/dev.kdrag0n.MacVirt` | regenerates |

### Custom targets (code)

| id | How | Tier, flags |
|---|---|---|
| npm | `npm cache clean --force`, then remove `~/.npm/_npx` | redownload |
| pnpm | `pnpm store prune` | redownload |
| go.modcache | `go clean -modcache` | redownload |
| cargo.registry | remove `~/.cargo/registry/cache` and `src`, keep `index` | redownload |
| ios.simulators | `simctl delete unavailable` with retry (only devices whose runtime is gone, they cannot boot anyway) | regenerates |
| ios.runtimes | one item per runtime, `simctl runtime delete <uuid>` | redownload, heavy; booted runtime is inUse |
| ios.dyld | one item per runtime folder | regenerates, needsAdmin |
| docker.buildcache | `docker builder prune -a -f` | regenerates |
| docker.images | `docker container prune -f` then `docker image prune -a -f` (no volumes, no build cache, that is `docker.buildcache`) | dataLoss, always shows the red warning because locally built images are removed too |

### Project rules

The scanner walks the configured project roots and prunes the folders in section 7. It evaluates every rule on every folder it visits (see the nested projects decision in section 2). Artifacts are resolved relative to the folder that holds the marker; the scanner never finds artifacts by walking into pruned folders.

| Stack | Marker | Artifacts | Tier |
|---|---|---|---|
| Flutter | `pubspec.yaml` with `sdk: flutter` | `build`, `.dart_tool` | regenerates |
| Node | `package.json` | `node_modules` (redownload), `.next .nuxt .output dist .svelte-kit .turbo .angular/cache .parcel-cache .expo .astro` (regenerates) | mixed |
| Rust | `Cargo.toml` | `target` (via `cargo clean`, fall back to delete) | regenerates |
| PHP | `composer.json` and `composer.lock` | `vendor` | redownload |
| Laravel | `artisan` and `composer.json` | `storage/framework/cache/data`, `storage/framework/views`, `storage/logs`, and the `.php` files in `bootstrap/cache` (by enumeration, not a glob) | regenerates |
| WordPress | `wp-config.php` | `wp-content/cache`, `wp-content/upgrade` only. Never `uploads`, `plugins`, `themes` | regenerates |
| Python | `pyproject.toml`, `requirements.txt`, `setup.py` or `Pipfile` | any direct child folder with a `pyvenv.cfg` (redownload); `.pytest_cache .mypy_cache .ruff_cache .tox` at the project root and `__pycache__` anywhere below it, outside pruned folders (regenerates) | mixed |
| iOS | `Podfile.lock` / `Package.swift` | `Pods` (redownload), `.build` (regenerates) | mixed |
| Android / JVM | `build.gradle`, `build.gradle.kts`, `settings.gradle*` | `build`, `.gradle`, `.cxx`, `app/build` | regenerates |
| Maven | `pom.xml` | `target` | regenerates |
| Ruby | `Gemfile.lock` | `vendor/bundle` | redownload |
| .NET | `*.csproj`, `*.sln` | `bin`, `obj` | regenerates |
| Elixir | `mix.exs` | `_build`, `deps` | regenerates / redownload |
| Terraform | `*.tf` | `.terraform` | redownload |

The project view groups artifacts per project, shows last modified and a "dormant" tag.

## 9. Version managers

One protocol, one type per tool. All show: installed versions with size, which projects pin each version, and a lock on the active and default version (locked rows have no checkbox).

| Tool | List | Pin files | Remove |
|---|---|---|---|
| fvm | `fvm list` (cache dir line) | `.fvmrc`, `.fvm/fvm_config.json` | `fvm remove <v>` |
| nvm | through `bash -c 'source $NVM_DIR/nvm.sh; nvm ls'` | `.nvmrc` (prefix match) | `nvm uninstall <v>` |
| rustup | `rustup toolchain list` | `rust-toolchain.toml`, `rust-toolchain` | `rustup toolchain uninstall <t>` |
| pyenv | `pyenv versions --bare` | `.python-version` | `pyenv uninstall -f <v>` |
| sdkman | `~/.sdkman/candidates/<c>/` | `.sdkmanrc` | `sdk uninstall <c> <v>` |
| mise | `mise ls --json` | `.tool-versions`, `mise.toml` | `mise uninstall <tool>@<v>` |

Pin files are searched in the configured project roots. Removal for version managers and runtimes is measured on the version's folder. Tier: redownload, heavy. Only installed tools show up.

## 10. Config and custom targets

`~/.config/phew/config.json`, created on first run:

```json
{
  "version": 1,
  "projectRoots": ["~/Documents/Projects"],
  "dormantDays": 14,
  "lowSpaceAlert": { "enabled": true, "thresholdGB": 20 },
  "customTargets": [
    { "id": "custom.unity-cache", "title": "Unity cache", "paths": ["~/Library/Unity/cache"], "tier": "redownload" }
  ]
}
```

- `projectRoots` is empty by default. On first run the app asks the user to pick folders (`NSOpenPanel`), the CLI asks in the terminal.
- Custom targets are path targets. Invalid entries are shown as errors in settings and skipped, never guessed.
- Settings has a button that opens the file in the default editor and a "Reload" button.

## 11. Menu bar app

`NSStatusItem` with an `NSPopover` holding the SwiftUI content (changed in M4 from `MenuBarExtra`, whose window slid under the menu bar when its height changed). Menu bar icon only (no Dock icon, `LSUIElement`). Optional short text next to the icon: free space, off by default.

Popover, top to bottom:
1. Header: volume name, available space and a bar (`volumeAvailableCapacityForImportantUsage`, the number Finder shows, labeled "Available"). Refresh button. "Scanned 12 min ago" or a progress line while scanning.
2. Summary: reclaimable (exactly what Quick clean would clean: preselected items that are ready), the size per tier (Regenerates, Redownload, Data loss), and a Quick clean button that opens the usual confirmation.
3. Group list (Xcode, Android, Flutter, Node, Python, PHP, Ruby, Java, Go, Rust, Docker, Editors, Versions, Projects, Custom), each with size. Click opens the group.
4. Group view: one row per item with checkbox, title, size, last used, tier badge, state badge, and a folder icon (Show in Finder). Version manager rows show "used by N projects" and a lock icon. Project rows expand to their artifacts.
5. Footer when something is checked: "Clean selected: N items, X GB".
6. Gear: settings (appearance, project roots, dormant days, launch at login, low space alert on/off and threshold, custom targets, FDA status, install CLI).

Clean flow inside the popover (no separate window):
- In-use items are never cleaned and never preselected. They can still be ticked: the confirmation then lists them under "Skipped, in use" with what is running and what to do ("Xcode is running. Quit Xcode to clean DerivedData."). If an app starts between the confirmation and the delete, the item is skipped and listed in the receipt as "skipped, in use", not as a failure.
- Clean (per item or bulk) shows an inline confirmation view: list of items, total size, tier per item. `dataLoss` items get a red line saying what is lost. `needsAdmin` items are confirmed and run separately with the admin prompt (`osascript ... with administrator privileges`).
- During the clean: progress per item. The popover may close; the clean continues and the menu bar icon shows activity.
- Receipt: "Phew. 42.3 GB freed." using measured bytes, plus failures per item with the reason. Volume free space before and after.

FDA:
- Check by trying to read a TCC-protected path (for example `~/Library/Containers/com.apple.Safari`). Recheck when the popover opens.
- Items with `needsFDA` while FDA is missing: shown dimmed with size unknown and an "Enable Full Disk Access" button that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` (verify the URL on the current macOS).

Scanning:
- `NSBackgroundActivityScheduler`, interval 2 hours, so macOS can delay it on battery or under load. The Refresh button runs the same scan now.
- Only one scan at a time; Refresh during a scan does nothing. Old results stay visible until the new scan finishes.
- Results are cached on disk (`~/Library/Caches/com.dikaputra.phew/scan.json`) so the popover shows numbers right after launch.
- After a clean, rescan only the touched targets.

Appearance:
- Light and dark mode. Default follows the system; settings has System, Light, Dark (applied with `preferredColorScheme`). Colors come from semantic colors and asset catalog colors with light and dark variants, never hardcoded. Tier badges keep the same hue in both modes with contrast checked in each.

About (bottom of settings):
- App name, version and build (from `CFBundleShortVersionString` and `CFBundleVersion`), author "Dika Putra", and a "View on GitHub" link to `https://github.com/dika-putra/phew` that opens in the browser. Also "Report an issue" linking to the repo issues page. The repo is private until M6, so the links only work for others after it goes public.
- The CLI shows the same in `phew --version` (version and repo URL).

Low space notification:
- Local notification (`UNUserNotificationCenter`) when available space drops below a threshold. Default 20 GB, on by default, both changeable in settings. Permission is asked on first run.
- Checked every 15 minutes (reading free space is cheap, no scan) and after every scan.
- Notifies once per drop. It re-arms only after available space goes back above threshold plus 5 GB, so it does not repeat while the disk stays low.
- Text: "Only 14.2 GB left. Phew can free about 38 GB." The reclaimable number comes from the last scan, without `dataLoss` and `optIn` items. Clicking the notification opens the popover.

## 12. CLI

The CLI is a first-class way to use Phew, not only a dev tool. Same core, same safety rules, same in-use behavior as the app (in-use items are listed as skipped with the reason).

Install:
- From the app: Settings has "Install command line tool", which links the `phew` binary inside the app bundle to `~/.local/bin/phew` (no admin) and says how to add `~/.local/bin` to `PATH` if it is missing.
- From source: `make install` builds release and copies `phew` to `~/.local/bin`.
- Homebrew tap later (section 15).

Help (swift-argument-parser generates the structure; every command fills in `abstract`, `discussion` with at least two examples, and help text for each option):
- `phew --help` and `phew help`: short description, list of commands, examples (`phew scan`, `phew clean xcode.deriveddata --dry-run`, `phew versions nvm`).
- `phew <command> --help` and `phew help <command>`: usage, options, examples.
- `phew --version`.
- `phew list [--group <g>]`: every target id with title, tier and flags, so users can find ids for `clean`.
- Unknown id in `clean`: error names the id and suggests close matches from `phew list`.

Commands:
- `phew scan [--json] [--group <g>]`: summary per group, then items. JSON schema is versioned.
- `phew clean <id...> [--dry-run | --yes]`: shows the plan, asks for confirmation unless `--yes`.
- `phew versions <fvm|nvm|rustup|pyenv|sdkman|mise|runtimes>`: interactive picker like the old script (numbers, `all`, `unused`).
- `phew config [--edit]`: print the config path and roots.
- `phew list`: see Help above.
- Spinner on stderr only when it is a terminal. Exit code non-zero when something failed to delete.

## 13. Tests

Use temp folders. Never touch real data.
- Hidden entries are deleted (`.analysis-driver` fixture).
- Symlinks are not followed. Paths outside the allowlist are refused. Custom targets pointing at `~` or `/` are rejected.
- `Receipt` uses measured bytes and flags claimed vs measured differences.
- Allocated size counts hard links once.
- Project scan: prune list, nested projects, Node workspaces, every rule in section 8, generic folder names without a marker are ignored, git-tracked artifact folders are skipped, dormant detection.
- Laravel and WordPress rules never select `uploads`, `plugins`, `themes`, or `storage/app`.
- Version managers: pin file parsing per tool, one project counted once, active and default locked.
- Parsers with captured sample output: `docker system df`, `simctl runtime list -j`, `simctl list devices -j`, `fvm list`, `rustup toolchain list`, `pyenv versions`.
- Config: invalid custom targets are reported, not loaded.
- Low space alert fires once when crossing the threshold and re-arms only above threshold plus 5 GB.
- In-use items are left out of a bulk plan and listed as skipped; an app starting after the plan makes the item "skipped, in use" in the receipt.
- CLI: `phew --help` and `phew help <command>` exit 0 and include the examples; unknown ids give suggestions.
- Tests that call real tools only run with `PHEW_REAL_TOOLS=1`.

## 14. Milestones

| M | Scope | Done when |
|---|---|---|
| 1 | Package skeleton, Shell, DiskSize, PathGuard, Config, catalog loader | tests pass |
| 2 | Path targets (section 8), Receipt, plan and execute | sizes match `everclean.sh` for shared targets, except where section 7 says the script is wrong (runtimes use `sizeBytes`, mounted volumes are not counted); tests pass |
| 3 | Project scanner with all rules, git-ignore check, dormant | `phew scan` lists projects under a fixture tree correctly |
| 4 | Menu bar app MVP: light and dark mode, About, header, summary, groups, item rows with checkboxes, Clean selected with confirmation, receipt, FDA badge and button, Refresh, 2-hour background scan, low space notification | can clean a fixture target from the popover and the receipt matches the measured change |
| 5 | Custom targets: simulators, runtimes, dyld, Docker, npm, pnpm, go, cargo; version managers | same behavior as `everclean.sh` for the ones it has |
| 6 | CLI polish (`--json`, `versions`, `list`, help text and examples for every command, install from the app and `make install`), README with screenshots and a CLI section, `NOTICE`, release zip with SHA-256 | clean install from the zip works on a second Mac or user account |

## 15. Distribution

No App Store (no sandbox: needs `~/Library`, runs `docker` and `xcrun`). Repo private until M6, then public under MIT. App: zip on GitHub Releases with SHA-256, README explains `xattr -cr`. CLI: build from source, Homebrew tap later. Whether Homebrew still accepts casks that are not notarized is unverified; check before relying on it.

