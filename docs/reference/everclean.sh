#!/bin/bash

# The shell may start inside a folder a cleanup deletes; subprocesses then print getcwd errors
cd "$HOME" || exit 1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verbose output goes here; the menu loop asks whether to show it after each action
LOG_FILE=$(mktemp)
trap 'spin_stop; rm -f "$LOG_FILE"' EXIT

# Spinner on stderr while something slow runs; always spin_stop before printing or prompting
SPIN_PID=""
spin_start() {
    [ -t 2 ] || return
    msg="$1"
    (
        i=0
        while true; do
            case $((i % 4)) in 0) c='|' ;; 1) c='/' ;; 2) c='-' ;; 3) c='\' ;; esac
            printf '\r%b%s%b %s ' "$CYAN" "$c" "$NC" "$msg" >&2
            i=$((i + 1))
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
}
spin_stop() {
    [ -n "$SPIN_PID" ] || return
    kill "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    SPIN_PID=""
    printf '\r\033[K' >&2
}

# Set by show_all_sizes; FREED_KB is added up by every clean step. Both print last.
SUMMARY_TEXT=""
FREED_KB=0

log() { echo -e "$*" >> "$LOG_FILE"; }

# banner COLOR TITLE: full-width separator line with a title
banner() { echo -e "\n$1━━━━━━━━━━━━━━━━ $2 ━━━━━━━━━━━━━━━━${NC}"; }

# Log first, then the summary at the very end of the output
offer_log() {
    if [ -s "$LOG_FILE" ]; then
        read -p "Show log? (y/N): " show
        if [[ "$show" =~ ^[Yy]$ ]]; then
            banner "$CYAN" "LOG"
            cat "$LOG_FILE"
        fi
        : > "$LOG_FILE"
    fi

    if [ -n "$SUMMARY_TEXT" ]; then
        banner "$GREEN" "SUMMARY"
        echo -e "$SUMMARY_TEXT"
    elif [ "$FREED_KB" -gt 0 ]; then
        banner "$GREEN" "SUMMARY"
        echo -e "  ${GREEN}Total freed: $(human_kb "$FREED_KB")${NC}"
    fi
    SUMMARY_TEXT=""
    FREED_KB=0
}

# Function to show directory size
show_size() {
    dir_path="$1"
    if [ -d "$dir_path" ]; then
        size=$(du -sh "$dir_path" 2>/dev/null | cut -f1)
        echo -e "${BLUE}Size of $dir_path: ${GREEN}$size${NC}"
    else
        echo -e "${RED}Directory $dir_path does not exist${NC}"
    fi
}

# Function to clean directory: one summary line, details go to the log
clean_dir() {
    dir_path="$1"
    if [ -d "$dir_path" ]; then
        spin_start "Cleaning ${dir_path/#$HOME/~}..."
        before_kb=$(path_size_kb "$dir_path")
        # find, not "$dir"/*: the glob skips hidden entries such as .analysis-driver
        find "$dir_path" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
        after_kb=$(path_size_kb "$dir_path")
        spin_stop
        FREED_KB=$((FREED_KB + before_kb - after_kb))
        log "${YELLOW}Cleaned${NC} $dir_path: $(human_kb "$before_kb") -> ${GREEN}$(human_kb "$after_kb")${NC}"
        echo -e "${GREEN}Cleaned $dir_path (freed $(human_kb "$((before_kb - after_kb))"))${NC}"
    else
        log "Skipped, not found: $dir_path"
    fi
}

# Fails fast with a clear message if docker isn't installed or Docker Desktop isn't running
docker_ready() {
    command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker not installed${NC}"; return 1; }
    docker info >/dev/null 2>&1 || { echo -e "${RED}Docker daemon not reachable — start Docker Desktop first${NC}"; return 1; }
}

# Sum of docker system df's reclaimable column, converted to KB (0 if docker isn't usable)
docker_reclaimable_kb() {
    docker_ready >/dev/null 2>&1 || { echo 0; return; }
    total_kb=0
    while read -r val; do
        num=$(echo "$val" | sed -E 's/^([0-9.]+).*/\1/')
        unit=$(echo "$val" | sed -E 's/^[0-9.]+([A-Za-z]+).*/\1/')
        case "$unit" in
            B)  kb=$(awk "BEGIN{printf \"%d\", $num/1024}") ;;
            KB) kb=$(awk "BEGIN{printf \"%d\", $num}") ;;
            MB) kb=$(awk "BEGIN{printf \"%d\", $num*1024}") ;;
            GB) kb=$(awk "BEGIN{printf \"%d\", $num*1024*1024}") ;;
            TB) kb=$(awk "BEGIN{printf \"%d\", $num*1024*1024*1024}") ;;
            *)  kb=0 ;;
        esac
        total_kb=$((total_kb + kb))
    done < <(docker system df --format '{{.Reclaimable}}' 2>/dev/null)
    echo "$total_kb"
}

# Only removes build cache — images, containers, volumes all untouched
clean_docker_cache() {
    docker_ready || return
    before_kb=$(docker_reclaimable_kb)
    log "Docker usage before cleanup:\n$(docker system df)"
    read -p "Remove build cache only, reclaimable $(human_kb "$before_kb") (images/containers/volumes untouched)? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Cancelled${NC}"
        return
    fi
    spin_start "Pruning Docker build cache..."
    docker builder prune -a -f >> "$LOG_FILE" 2>&1
    log "Docker usage after cleanup:\n$(docker system df)"
    freed_kb=$((before_kb - $(docker_reclaimable_kb)))
    spin_stop
    FREED_KB=$((FREED_KB + freed_kb))
    echo -e "${GREEN}Docker build cache cleaned (freed $(human_kb "$freed_kb"))${NC}"
}

# Stops running containers, cleans containers/images/build cache, keeps volumes (data safe)
clean_docker() {
    docker_ready || return
    before_kb=$(docker_reclaimable_kb)
    log "Docker usage before cleanup:\n$(docker system df)"
    running=$(docker ps -q)
    if [ -n "$running" ]; then
        echo -e "${BLUE}Running containers will be stopped:${NC}"
        docker ps --format '  {{.Names}} ({{.Image}})'
    fi
    echo -e "${BLUE}This stops running containers and removes: containers, unused images, unused networks, build cache. Volumes are kept.${NC}"
    read -p "Proceed? (reclaimable now: $(human_kb "$before_kb")) (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Cancelled${NC}"
        return
    fi
    spin_start "Stopping containers and pruning Docker..."
    [ -n "$running" ] && docker stop $running >> "$LOG_FILE" 2>&1
    docker system prune -a -f >> "$LOG_FILE" 2>&1
    log "Docker usage after cleanup:\n$(docker system df)"
    freed_kb=$((before_kb - $(docker_reclaimable_kb)))
    spin_stop
    FREED_KB=$((FREED_KB + freed_kb))
    echo -e "${GREEN}Docker cleaned (freed $(human_kb "$freed_kb"))${NC}"
}

clean_macos_caches() {
    clean_dir ~/Library/Logs
    clean_dir ~/Library/Caches
}

clean_ios_cache() {
    clean_dir ~/Library/Caches/com.apple.dt.Xcode
    clean_dir ~/Library/Developer/CoreSimulator/Caches
}

clean_ios_build() {
    clean_dir ~/Library/Developer/Xcode/DerivedData
    clean_dir ~/Library/Developer/Xcode/Archives
}

# Only removes simulators whose runtime is gone; usable simulators and their app data stay
clean_simulators() {
    command -v xcrun >/dev/null 2>&1 || { echo -e "${RED}xcrun not found (install Xcode command line tools)${NC}"; return; }
    sim_dir=~/Library/Developer/CoreSimulator/Devices
    before_kb=$(path_size_kb "$sim_dir")
    spin_start "Removing unavailable simulators..."
    # Right after a runtime delete CoreSimulator can lag before it marks its simulators unavailable
    for attempt in 1 2 3; do
        xcrun simctl delete unavailable >> "$LOG_FILE" 2>&1
        [ "$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(')" -eq 0 ] && break
        sleep 3
    done
    after_kb=$(path_size_kb "$sim_dir")
    spin_stop
    left=$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(')
    [ "$left" -gt 0 ] && echo -e "${RED}$left unavailable simulators are still left (see log)${NC}"
    FREED_KB=$((FREED_KB + before_kb - after_kb))
    echo -e "${GREEN}Removed unavailable simulators (freed $(human_kb "$((before_kb - after_kb))"))${NC}"
}

# uuid|name|build|bytes|simulator count|booted count|days since last used (99999 = never)
runtime_lines() {
    python3 - <<'PY'
import json, subprocess
from datetime import datetime, timezone
def run(*a):
    return json.loads(subprocess.run(a, capture_output=True, text=True).stdout or "{}")
runtimes = run("xcrun", "simctl", "runtime", "list", "-j")
devices = run("xcrun", "simctl", "list", "devices", "-j").get("devices", {})
now = datetime.now(timezone.utc)
for uuid, v in runtimes.items():
    rid = v.get("runtimeIdentifier")
    name = (rid or "").rsplit(".", 1)[-1].replace("-", " ", 1).replace("-", ".")
    devs = devices.get(rid, [])
    booted = sum(1 for d in devs if d.get("state") == "Booted")
    used = v.get("lastUsedAt")
    days = (now - datetime.fromisoformat(used.replace("Z", "+00:00"))).days if used else 99999
    print(f"{uuid}|{name}|{v.get('build')}|{v.get('sizeBytes', 0)}|{len(devs)}|{booted}|{days}")
PY
}

# Pick installed simulator runtimes to delete, then remove the simulators left without a runtime
clean_ios_runtimes() {
    command -v xcrun >/dev/null 2>&1 || { echo -e "${RED}xcrun not found (install Xcode command line tools)${NC}"; return; }
    lines=$(runtime_lines)
    if [ -z "$lines" ]; then
        echo -e "${RED}No simulator runtimes found${NC}"
        return
    fi

    echo -e "${CYAN}Installed simulator runtimes:${NC}"
    i=0
    while IFS='|' read -r uuid name build bytes count booted days; do
        i=$((i + 1))
        if [ "$days" -ge 99999 ]; then used="never used"; else used="used ${days}d ago"; fi
        [ "$booted" -gt 0 ] && used="${RED}IN USE, $booted booted${NC}"
        printf "  %d) %-10s (%s)  ${YELLOW}%-9s${NC}  %2s simulators  %b\n" "$i" "$name" "$build" "$(human_kb "$((bytes / 1024))")" "$count" "$used"
    done <<< "$lines"

    read -p "Delete which? (numbers like '1 3', 'all', 'unused' = not used for 30+ days, 'unused 60' = 60+ days, Enter to cancel): " pick
    if [ -z "$pick" ]; then
        echo -e "${RED}Cancelled${NC}"
        return
    fi

    min_days=""
    if [[ "$pick" == unused* ]]; then
        min_days="${pick#unused}"
        min_days="${min_days// /}"
        min_days="${min_days:-30}"
        [[ "$min_days" =~ ^[0-9]+$ ]] || { echo -e "${RED}Invalid days: $min_days${NC}"; return; }
    fi

    selected=""
    booted_selected=0
    i=0
    while IFS='|' read -r uuid name build bytes count booted days; do
        i=$((i + 1))
        pick_it=0
        if [ -n "$min_days" ]; then
            [ "$booted" -eq 0 ] && [ "$days" -ge "$min_days" ] && pick_it=1
        elif [ "$pick" = "all" ] || [[ " $pick " == *" $i "* ]]; then
            pick_it=1
        fi
        if [ "$pick_it" -eq 1 ]; then
            selected+="$uuid|$name|$bytes"$'\n'
            [ "$booted" -gt 0 ] && booted_selected=1
        fi
    done <<< "$lines"
    if [ -z "$selected" ]; then
        echo -e "${RED}Nothing matches that selection${NC}"
        return
    fi

    names=$(echo -n "$selected" | awk -F'|' '{printf "%s%s", sep, $2; sep=", "}')
    total_bytes=$(echo -n "$selected" | awk -F'|' '{s+=$3} END{printf "%d", s}')
    [ "$booted_selected" -eq 1 ] && echo -e "${RED}Some selected runtimes have booted simulators; they will be shut down.${NC}"
    read -p "Delete $names (~$(human_kb "$((total_bytes / 1024))"))? Their simulators are removed too, and re-downloading from Apple is needed to get them back. (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Cancelled${NC}"
        return
    fi

    spin_start "Deleting runtimes..."
    while IFS='|' read -r uuid name bytes; do
        [ -n "$uuid" ] || continue
        log "${YELLOW}Deleting runtime${NC} $name ($uuid)"
        xcrun simctl runtime delete "$uuid" >> "$LOG_FILE" 2>&1
    done <<< "$selected"
    spin_stop

    # Count only what is really gone: a selected runtime that still shows up failed to delete
    remaining=$(runtime_lines | cut -d'|' -f1)
    freed_bytes=0
    while IFS='|' read -r uuid name bytes; do
        [ -n "$uuid" ] || continue
        if echo "$remaining" | grep -q "$uuid"; then
            echo -e "${RED}Could not delete $name (see log)${NC}"
        else
            freed_bytes=$((freed_bytes + bytes))
        fi
    done <<< "$selected"
    FREED_KB=$((FREED_KB + freed_bytes / 1024))
    echo -e "${GREEN}Deleted runtimes: freed ~$(human_kb "$((freed_bytes / 1024))")${NC}"
    clean_simulators
}

clean_npm_cache() {
    command -v npm >/dev/null 2>&1 || { echo -e "${RED}npm not found${NC}"; return; }
    npm_cache=$(npm config get cache)
    before_kb=$(path_size_kb "$npm_cache")
    spin_start "Cleaning npm cache..."
    npm cache clean --force >> "$LOG_FILE" 2>&1
    # npx installs live in _npx, which "npm cache clean" leaves alone; npx downloads them again when needed
    rm -rf "$npm_cache/_npx"
    after_kb=$(path_size_kb "$npm_cache")
    spin_stop
    FREED_KB=$((FREED_KB + before_kb - after_kb))
    echo -e "${GREEN}Cleaned npm cache (freed $(human_kb "$((before_kb - after_kb))"))${NC}"
}

# Slow to redownload/reinstall; the SDK dir already contains system-images
clean_heavy() {
    read -p "Also delete iOS DeviceSupport, Android AVDs and Android SDK (slow to redownload)? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${RED}Skipped heavy items${NC}"; return; }
    clean_dir ~/Library/Developer/Xcode/iOS\ DeviceSupport
    clean_dir ~/.android/avd
    clean_dir ~/Library/Android/sdk
}

# Removes only packages no project references anymore
clean_pnpm_store() {
    command -v pnpm >/dev/null 2>&1 || { echo -e "${RED}pnpm not found${NC}"; return; }
    store=$(pnpm store path 2>/dev/null)
    spin_start "Pruning pnpm store..."
    before_kb=$(path_size_kb "$store")
    pnpm store prune >> "$LOG_FILE" 2>&1
    after_kb=$(path_size_kb "$store")
    spin_stop
    FREED_KB=$((FREED_KB + before_kb - after_kb))
    echo -e "${GREEN}Pruned pnpm store (freed $(human_kb "$((before_kb - after_kb))"))${NC}"
}

clean_go_modcache() {
    command -v go >/dev/null 2>&1 || { echo -e "${RED}go not found${NC}"; return; }
    modcache=$(go env GOMODCACHE)
    spin_start "Cleaning Go module cache..."
    before_kb=$(path_size_kb "$modcache")
    go clean -modcache >> "$LOG_FILE" 2>&1
    after_kb=$(path_size_kb "$modcache")
    spin_stop
    FREED_KB=$((FREED_KB + before_kb - after_kb))
    echo -e "${GREEN}Cleaned Go module cache (freed $(human_kb "$((before_kb - after_kb))"))${NC}"
}

# Downloaded crates; cargo fetches them again on the next build. The registry index stays.
clean_cargo_registry() {
    clean_dir ~/.cargo/registry/cache
    clean_dir ~/.cargo/registry/src
}

# Root-owned simulator dyld cache, one folder per runtime. CoreSimulator rebuilds a folder when its
# runtime is used again (first simulator boot can be slow). Pick which runtimes' caches to delete.
clean_sim_dyld_cache() {
    root=/Library/Developer/CoreSimulator/Caches/dyld
    [ -d "$root" ] || { echo -e "${RED}$root not found${NC}"; return; }
    rt=$(runtime_lines)

    dirs=(); labels=(); sizes=(); days_a=(); booted_a=()
    for dir in "$root"/*/com.apple.CoreSimulator.SimRuntime.*; do
        [ -d "$dir" ] || continue
        name="${dir##*/}"
        build="${name##*.}"
        info=$(echo "$rt" | awk -F'|' -v b="$build" '$3==b{print $6"|"$7}')
        if [ -n "$info" ]; then
            booted="${info%%|*}"; days="${info##*|}"
        else
            booted=0; days=-1
        fi
        dirs+=("$dir"); labels+=("${name#com.apple.CoreSimulator.SimRuntime.}")
        sizes+=("$(path_size_kb "$dir")"); days_a+=("$days"); booted_a+=("$booted")
    done
    if [ "${#dirs[@]}" -eq 0 ]; then
        echo -e "${RED}No dyld cache folders found${NC}"
        return
    fi

    echo -e "${CYAN}Simulator dyld cache per runtime:${NC}"
    for i in "${!dirs[@]}"; do
        if [ "${days_a[$i]}" -lt 0 ]; then status="${YELLOW}runtime removed${NC}"
        elif [ "${booted_a[$i]}" -gt 0 ]; then status="${RED}IN USE, ${booted_a[$i]} booted${NC}"
        elif [ "${days_a[$i]}" -ge 99999 ]; then status="never used"
        else status="used ${days_a[$i]}d ago"; fi
        printf "  %d) %-22s ${YELLOW}%-9s${NC}  %b\n" "$((i + 1))" "${labels[$i]}" "$(human_kb "${sizes[$i]}")" "$status"
    done

    read -p "Delete which? (numbers like '1 3', 'all', 'unused' = runtime removed or not used 30+ days, 'unused 60', Enter to cancel): " pick
    [ -n "$pick" ] || { echo -e "${RED}Cancelled${NC}"; return; }

    min_days=""
    if [[ "$pick" == unused* ]]; then
        min_days="${pick#unused}"; min_days="${min_days// /}"; min_days="${min_days:-30}"
        [[ "$min_days" =~ ^[0-9]+$ ]] || { echo -e "${RED}Invalid days: $min_days${NC}"; return; }
    fi

    sel=(); total_kb=0
    for i in "${!dirs[@]}"; do
        pick_it=0
        if [ -n "$min_days" ]; then
            if [ "${days_a[$i]}" -lt 0 ] || { [ "${booted_a[$i]}" -eq 0 ] && [ "${days_a[$i]}" -ge "$min_days" ]; }; then pick_it=1; fi
        elif [ "$pick" = "all" ] || [[ " $pick " == *" $((i + 1)) "* ]]; then
            pick_it=1
        fi
        if [ "$pick_it" -eq 1 ]; then sel+=("$i"); total_kb=$((total_kb + sizes[i])); fi
    done
    [ "${#sel[@]}" -gt 0 ] || { echo -e "${RED}Nothing matches that selection${NC}"; return; }

    read -p "Delete ${#sel[@]} dyld cache folder(s), ~$(human_kb "$total_kb"), with sudo? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${RED}Cancelled${NC}"; return; }
    sudo -v || { echo -e "${RED}sudo failed${NC}"; return; }

    spin_start "Deleting simulator dyld cache..."
    for i in "${sel[@]}"; do
        log "${YELLOW}Deleting dyld cache${NC} ${labels[$i]}"
        sudo rm -rf "${dirs[$i]}" >> "$LOG_FILE" 2>&1
    done
    spin_stop
    freed_kb=0
    for i in "${sel[@]}"; do
        if [ -d "${dirs[$i]}" ]; then
            echo -e "${RED}Could not delete ${labels[$i]} (see log)${NC}"
        else
            freed_kb=$((freed_kb + sizes[i]))
        fi
    done
    FREED_KB=$((FREED_KB + freed_kb))
    echo -e "${GREEN}Cleaned simulator dyld cache (freed ~$(human_kb "$freed_kb"))${NC}"
}

# Electron-based editors: Application Support folder name and the app bundle name
IDE_APPS=("Devin:Devin" "Cursor:Cursor" "Windsurf:Windsurf" "Code:Visual Studio Code")
# Cache-only subfolders; settings, extensions and workspace state are not in this list
IDE_CACHE_SUBDIRS=(Cache CachedData CachedExtensionVSIXs "Code Cache" GPUCache DawnGraphiteCache DawnWebGPUCache logs)

ide_cache_dirs() {
    for pair in "${IDE_APPS[@]}"; do
        support=~/"Library/Application Support/${pair%%:*}"
        for sub in "${IDE_CACHE_SUBDIRS[@]}"; do
            [ -d "$support/$sub" ] && echo "$support/$sub"
        done
    done
}

# Skips an editor while it is running, so its caches are not pulled out from under it
clean_ide_caches() {
    for pair in "${IDE_APPS[@]}"; do
        dir="${pair%%:*}"; bundle="${pair##*:}"
        support=~/"Library/Application Support/$dir"
        [ -d "$support" ] || continue
        if pgrep -f "/$bundle.app/Contents/MacOS/" >/dev/null 2>&1; then
            echo -e "${YELLOW}$bundle is running, skipped (quit it first)${NC}"
            continue
        fi
        for sub in "${IDE_CACHE_SUBDIRS[@]}"; do
            clean_dir "$support/$sub"
        done
    done
}

# .fvmrc, .fvm/fvm_config.json and .nvmrc files under PROJECT_ROOTS (one path per line)
find_version_files() {
    for root in "${PROJECT_ROOTS[@]}"; do
        [ -d "$root" ] || continue
        find "$root" \( -name node_modules -o -name build -o -name .git -o -name .dart_tool -o -name Pods -o -name target -o -name dist -o -name .next -o -name .opencode -o -name .claude \) -prune -o \( -name .fvmrc -o -name fvm_config.json -o -name .nvmrc \) -type f -print 2>/dev/null
    done
}

# Generic picker over the PV_* arrays (PV_LABELS, PV_SIZES in KB, PV_NOTES, PV_USED count, PV_LOCK 1 = cannot remove).
# Sets PV_SEL (indexes) and PV_TOTAL_KB. Returns 1 when nothing is chosen or the user declines.
pick_versions() {
    what="$1"
    for i in "${!PV_LABELS[@]}"; do
        printf "  %d) %-12s ${YELLOW}%-9s${NC}  %b\n" "$((i + 1))" "${PV_LABELS[$i]}" "$(human_kb "${PV_SIZES[$i]}")" "${PV_NOTES[$i]}"
    done
    read -p "Remove which $what? (numbers like '1 3', 'unused' = not used by any project, Enter to cancel): " pick
    [ -n "$pick" ] || { echo -e "${RED}Cancelled${NC}"; return 1; }

    PV_SEL=(); PV_TOTAL_KB=0; used_selected=0
    for i in "${!PV_LABELS[@]}"; do
        pick_it=0
        if [ "$pick" = "unused" ]; then
            [ "${PV_USED[$i]}" -eq 0 ] && pick_it=1
        elif [[ " $pick " == *" $((i + 1)) "* ]]; then
            pick_it=1
        fi
        [ "${PV_LOCK[$i]}" -eq 1 ] && pick_it=0
        if [ "$pick_it" -eq 1 ]; then
            PV_SEL+=("$i"); PV_TOTAL_KB=$((PV_TOTAL_KB + PV_SIZES[i]))
            [ "${PV_USED[$i]}" -gt 0 ] && used_selected=1
        fi
    done
    [ "${#PV_SEL[@]}" -gt 0 ] || { echo -e "${RED}Nothing removable matches that selection${NC}"; return 1; }

    chosen=""
    for i in "${PV_SEL[@]}"; do chosen+="${PV_LABELS[$i]} "; done
    [ "$used_selected" -eq 1 ] && echo -e "${RED}Some selected versions are still used by projects listed above.${NC}"
    read -p "Remove $chosen(~$(human_kb "$PV_TOTAL_KB")) and download again if needed? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${RED}Cancelled${NC}"; return 1; }
}

# "a, b, c +2" (base names) from a newline-separated list of paths
short_names() {
    echo "$1" | awk -F/ 'NF{n++; if(n<=3){printf "%s%s", (n>1?", ":""), $NF}} END{if(n>3) printf " +%d", n-3}'
}

# Pick installed Flutter SDK versions (fvm) to remove
fvm_remove_versions() {
    command -v fvm >/dev/null 2>&1 || { echo -e "${RED}fvm not found${NC}"; return; }
    vdir=$(fvm list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^Cache directory: *//p' | head -1)
    vdir="${vdir:-$HOME/fvm/versions}"
    [ -d "$vdir" ] || { echo -e "${RED}$vdir not found${NC}"; return; }

    spin_start "Scanning projects for .fvmrc..."
    files=$(find_version_files)
    PV_LABELS=(); PV_SIZES=(); PV_NOTES=(); PV_USED=(); PV_LOCK=()
    for dir in "$vdir"/*/; do
        [ -d "$dir" ] || continue
        v=$(basename "$dir")
        users=""
        while IFS= read -r f; do
            case "$f" in *.fvmrc|*fvm_config.json) ;; *) continue ;; esac
            want=$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p;s/.*"flutterSdkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
            [ "$want" = "$v" ] || continue
            proj="$(dirname "$f")"; [ "$(basename "$proj")" = ".fvm" ] && proj="$(dirname "$proj")"
            users+="$proj"$'\n'
        done <<< "$files"
        users=$(echo -n "$users" | sort -u)
        n=$(echo -n "$users" | grep -c .)
        PV_LABELS+=("$v"); PV_SIZES+=("$(path_size_kb "$dir")"); PV_USED+=("$n"); PV_LOCK+=(0)
        if [ "$n" -gt 0 ]; then PV_NOTES+=("used by $n: $(short_names "$users")"); else PV_NOTES+=("not used by any project"); fi
    done
    spin_stop
    [ "${#PV_LABELS[@]}" -gt 0 ] || { echo -e "${RED}No Flutter versions installed${NC}"; return; }

    echo -e "${CYAN}Installed Flutter versions (fvm):${NC}"
    pick_versions "Flutter versions" || return

    spin_start "Removing Flutter versions..."
    for i in "${PV_SEL[@]}"; do
        log "${YELLOW}fvm remove${NC} ${PV_LABELS[$i]}"
        fvm remove "${PV_LABELS[$i]}" >> "$LOG_FILE" 2>&1
    done
    spin_stop
    freed_kb=0
    for i in "${PV_SEL[@]}"; do
        if [ -d "$vdir/${PV_LABELS[$i]}" ]; then echo -e "${RED}Could not remove ${PV_LABELS[$i]} (see log)${NC}"
        else freed_kb=$((freed_kb + PV_SIZES[i])); fi
    done
    FREED_KB=$((FREED_KB + freed_kb))
    echo -e "${GREEN}Removed Flutter versions (freed $(human_kb "$freed_kb"))${NC}"
}

# Pick installed Node versions (nvm) to remove; the active and default versions are locked
nvm_remove_versions() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    [ -s "$NVM_DIR/nvm.sh" ] || { echo -e "${RED}nvm not found in $NVM_DIR${NC}"; return; }
    vdir="$NVM_DIR/versions/node"
    [ -d "$vdir" ] || { echo -e "${RED}$vdir not found${NC}"; return; }

    spin_start "Scanning projects for .nvmrc..."
    files=$(find_version_files)
    active=$(bash -c 'source "$NVM_DIR/nvm.sh" >/dev/null 2>&1; nvm current' 2>/dev/null)
    default=$(bash -c 'source "$NVM_DIR/nvm.sh" >/dev/null 2>&1; nvm version default' 2>/dev/null)
    PV_LABELS=(); PV_SIZES=(); PV_NOTES=(); PV_USED=(); PV_LOCK=()
    for dir in "$vdir"/*/; do
        [ -d "$dir" ] || continue
        v=$(basename "$dir")
        users=""
        while IFS= read -r f; do
            case "$f" in *.nvmrc) ;; *) continue ;; esac
            req=$(head -1 "$f" | tr -d ' \r'); req="${req#v}"
            [[ "$req" =~ ^[0-9][0-9.]*$ ]] || continue
            case "${v#v}" in "$req"|"$req".*) users+="$(dirname "$f")"$'\n' ;; esac
        done <<< "$files"
        users=$(echo -n "$users" | sort -u)
        n=$(echo -n "$users" | grep -c .)
        lock=0; note=""
        if [ "$v" = "$active" ]; then lock=1; note="${RED}active in this shell, locked${NC}"
        elif [ "$v" = "$default" ]; then lock=1; note="${RED}nvm default, locked${NC}"
        elif [ "$n" -gt 0 ]; then note="used by $n (.nvmrc): $(short_names "$users")"
        else note="not used by any project"; fi
        PV_LABELS+=("$v"); PV_SIZES+=("$(path_size_kb "$dir")"); PV_USED+=("$n"); PV_LOCK+=("$lock"); PV_NOTES+=("$note")
    done
    spin_stop
    [ "${#PV_LABELS[@]}" -gt 0 ] || { echo -e "${RED}No Node versions installed${NC}"; return; }

    echo -e "${CYAN}Installed Node versions (nvm):${NC}"
    pick_versions "Node versions" || return

    spin_start "Removing Node versions..."
    for i in "${PV_SEL[@]}"; do
        log "${YELLOW}nvm uninstall${NC} ${PV_LABELS[$i]}"
        NVM_TARGET="${PV_LABELS[$i]}" bash -c 'source "$NVM_DIR/nvm.sh" >/dev/null 2>&1; nvm uninstall "$NVM_TARGET"' >> "$LOG_FILE" 2>&1
    done
    spin_stop
    freed_kb=0
    for i in "${PV_SEL[@]}"; do
        if [ -d "$vdir/${PV_LABELS[$i]}" ]; then echo -e "${RED}Could not remove ${PV_LABELS[$i]} (see log)${NC}"
        else freed_kb=$((freed_kb + PV_SIZES[i])); fi
    done
    FREED_KB=$((FREED_KB + freed_kb))
    echo -e "${GREEN}Removed Node versions (freed $(human_kb "$freed_kb"))${NC}"
}

# Everything except the heavy items
clean_light() {
    clean_macos_caches
    clean_ios_cache
    clean_ios_build
    clean_simulators
    clean_dir ~/.pub-cache
    clean_dir ~/.dartServer
    clean_dir ~/.gradle
    clean_npm_cache
    clean_pnpm_store
    clean_dir ~/.cache/puppeteer
    clean_cargo_registry
    clean_go_modcache
    clean_ide_caches
    clean_all_projects
    clean_docker_cache
}

# Scan dirs for all projects (flutter -> build/.dart_tool, node -> node_modules)
PROJECT_ROOTS=(~/Documents/Work ~/Documents/Projects)

# Sum of du -sk (KB) across given paths, skipping ones that don't exist
path_size_kb() {
    total=0
    for p in "$@"; do
        [ -e "$p" ] || continue
        total=$((total + $(du -sk "$p" 2>/dev/null | cut -f1)))
    done
    echo "$total"
}

human_kb() {
    kb=$1
    if [ "$kb" -ge 1048576 ]; then
        awk "BEGIN{printf \"%.2f GB\", $kb/1048576}"
    else
        awk "BEGIN{printf \"%.1f MB\", $kb/1024}"
    fi
}

# Paths a plan_file entry covers, space separated (used for size + delete)
entry_paths() {
    case "$1" in
        FLUTTER) echo "$2/build" "$2/.dart_tool" ;;
        RUST)    echo "$2/target" ;;
        NODE)    echo "$2/node_modules" "$2/.next" "$2/.nuxt" "$2/.output" "$2/dist" "$2/.svelte-kit" "$2/.turbo" ;;
    esac
}

# Scans PROJECT_ROOTS, writes TYPE|path lines to a tmp file, echoes its path
scan_projects() {
    PRUNE=( -name node_modules -o -name build -o -name .dart_tool -o -name target -o -name dist -o -name .next -o -name .nuxt -o -name .output -o -name .svelte-kit -o -name .turbo -o -name .git -o -name .opencode -o -name .claude -o -name .cursor -o -name .windsurf -o -name .aider -o -name .continue -o -name .codeium )
    plan_file=$(mktemp)

    for root in "${PROJECT_ROOTS[@]}"; do
        [ -d "$root" ] || continue

        # Flutter projects: any pubspec.yaml depending on the flutter sdk
        find "$root" \( "${PRUNE[@]}" \) -prune -o -name pubspec.yaml -print 2>/dev/null | while read -r pubspec; do
            if grep -q "^[[:space:]]*sdk:[[:space:]]*flutter" "$pubspec" && grep -q "^[[:space:]]*flutter:" "$pubspec"; then
                echo "FLUTTER|$(dirname "$pubspec")" >> "$plan_file"
            fi
        done

        # Rust projects: any Cargo.toml -> target/
        find "$root" \( "${PRUNE[@]}" \) -prune -o -name Cargo.toml -print 2>/dev/null | while read -r cargo; do
            proj="$(dirname "$cargo")"
            [ -d "$proj/target" ] && echo "RUST|$proj" >> "$plan_file"
        done

        # Node/Next/Nuxt/Vite projects: any package.json not already inside node_modules
        find "$root" \( "${PRUNE[@]}" \) -prune -o -name package.json -print 2>/dev/null | while read -r pkg; do
            proj="$(dirname "$pkg")"
            [ -d "$proj/node_modules" ] && echo "NODE|$proj" >> "$plan_file"
        done
    done

    echo "$plan_file"
}

# Strips the matching PROJECT_ROOTS prefix so paths print short in listings
relpath() {
    proj="$1"
    for root in "${PROJECT_ROOTS[@]}"; do
        case "$proj" in
            "$root"/*) echo "${proj#"$root"/}"; return ;;
        esac
    done
    echo "$proj"
}

# Prints each plan_file entry with its size and a grand total; sets PLAN_TOTAL_KB
# Optional 2nd arg: hide entries below this many KB and print how many were hidden
print_plan() {
    plan_file="$1"
    min_kb="${2:-0}"
    PLAN_TOTAL_KB=0
    hidden=0
    while IFS='|' read -r type proj; do
        paths=$(entry_paths "$type" "$proj")
        size_kb=$(path_size_kb $paths)
        PLAN_TOTAL_KB=$((PLAN_TOTAL_KB + size_kb))
        if [ "$size_kb" -lt "$min_kb" ]; then
            hidden=$((hidden + 1))
            continue
        fi
        printf "  [%-7s] %-45s ${GREEN}%s${NC}\n" "$type" "$(relpath "$proj")" "$(human_kb "$size_kb")"
    done < "$plan_file"
    [ "$hidden" -gt 0 ] && echo -e "  ${BLUE}(+$hidden more under $(human_kb "$min_kb"))${NC}"
    echo -e "${BLUE}Total: $(human_kb "$PLAN_TOTAL_KB")${NC}"
}

CACHE_DIRS=(~/Library/Logs ~/Library/Caches ~/Library/Developer/Xcode/DerivedData ~/Library/Developer/Xcode/Archives ~/.pub-cache ~/.dartServer ~/.gradle ~/.npm ~/Library/pnpm ~/.cache/puppeteer ~/.cargo/registry/cache ~/.cargo/registry/src ~/go/pkg/mod)
while IFS= read -r d; do CACHE_DIRS+=("$d"); done < <(ide_cache_dirs)
HEAVY_DIRS=(~/Library/Developer/Xcode/iOS\ DeviceSupport ~/.android/avd ~/Library/Android/sdk)

show_all_sizes() {
    spin_start "Calculating sizes..."
    dir_lines=""
    cache_kb=0
    heavy_kb=0
    for d in "${CACHE_DIRS[@]}"; do
        kb=$(path_size_kb "$d")
        cache_kb=$((cache_kb + kb))
        dir_lines+="$(printf "    %-52s ${YELLOW}%s${NC}" "${d/#$HOME/~}" "$(human_kb "$kb")")"$'\n'
    done
    for d in "${HEAVY_DIRS[@]}"; do
        kb=$(path_size_kb "$d")
        heavy_kb=$((heavy_kb + kb))
        dir_lines+="$(printf "    %-52s ${YELLOW}%s${NC}" "${d/#$HOME/~}" "$(human_kb "$kb")")"$'\n'
    done
    runtime_kb=$(runtime_lines | awk -F'|' '{s+=$4} END{printf "%d", s/1024}')
    heavy_kb=$((heavy_kb + runtime_kb))
    dir_lines+="$(printf "    %-52s ${YELLOW}%s${NC} (real size, simctl)" "iOS simulator runtimes" "$(human_kb "$runtime_kb")")"$'\n'
    # Info only: already counted inside the SDK / not removable by an option
    sdk_images=~/Library/Android/sdk/system-images
    sim_devices=~/Library/Developer/CoreSimulator/Devices
    dir_lines+="$(printf "    %-52s ${YELLOW}%s${NC} (inside SDK)" "${sdk_images/#$HOME/~}" "$(human_kb "$(path_size_kb "$sdk_images")")")"$'\n'
    dir_lines+="$(printf "    %-52s ${YELLOW}%s${NC} (simulators)" "${sim_devices/#$HOME/~}" "$(human_kb "$(path_size_kb "$sim_devices")")")"$'\n'
    dyld=/Library/Developer/CoreSimulator/Caches/dyld
    dir_lines+="$(printf "    %-52s ${YELLOW}%s${NC} (needs sudo, menu 8)" "$dyld" "$(human_kb "$(path_size_kb "$dyld")")")"

    plan_file=$(scan_projects)
    build_kb=0
    if [ -s "$plan_file" ]; then
        while IFS='|' read -r type proj; do
            paths=$(entry_paths "$type" "$proj")
            build_kb=$((build_kb + $(path_size_kb $paths)))
        done < "$plan_file"
    fi

    docker_kb=$(docker_reclaimable_kb)
    total_kb=$((cache_kb + heavy_kb + build_kb + docker_kb))

    log "${CYAN}-- Project builds --${NC}"
    if [ -s "$plan_file" ]; then
        print_plan "$plan_file" 1024 >> "$LOG_FILE"
    else
        log "${RED}None found${NC}"
    fi

    log "\n${CYAN}-- Docker --${NC}"
    docker_ready >/dev/null 2>&1 && log "$(docker system df)"

    rm -f "$plan_file"
    spin_stop

    SUMMARY_TEXT="  ${CYAN}Directories${NC}
$dir_lines

  ${CYAN}By category${NC}
$(printf "    %-32s ${YELLOW}%s${NC}\n" "System caches:" "$(human_kb "$cache_kb")")
$(printf "    %-32s ${YELLOW}%s${NC}\n" "Heavy (SDK/AVD/runtimes/DeviceSupport):" "$(human_kb "$heavy_kb")")
$(printf "    %-32s ${YELLOW}%s${NC}\n" "Project builds:" "$(human_kb "$build_kb")")
$(printf "    %-32s ${YELLOW}%s${NC}\n" "Docker reclaimable:" "$(human_kb "$docker_kb")")

  ${GREEN}TOTAL: $(human_kb "$total_kb")${NC}"
}

# Optional arg limits the scan result to some types, e.g. "FLUTTER" or "NODE|RUST"
clean_all_projects() {
    types="${1:-FLUTTER|RUST|NODE}"
    spin_start "Scanning projects..."
    plan_file=$(scan_projects)
    grep -E "^($types)\|" "$plan_file" > "$plan_file.f"
    mv "$plan_file.f" "$plan_file"

    if [ ! -s "$plan_file" ]; then
        spin_stop
        echo -e "${RED}No projects to clean${NC}"
        rm -f "$plan_file"
        return
    fi

    list_file=$(mktemp)
    print_plan "$plan_file" > "$list_file"
    before_total=$PLAN_TOTAL_KB
    spin_stop

    echo -e "\n${BLUE}Found $(wc -l < "$plan_file" | tr -d ' ') projects to clean, $(human_kb "$before_total") total${NC}"
    read -p "Show the list of paths first? (y/N): " show
    [[ "$show" =~ ^[Yy]$ ]] && cat "$list_file"
    rm -f "$list_file"

    read -p "Proceed with deletion? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Cancelled${NC}"
        rm -f "$plan_file"
        return
    fi

    spin_start "Cleaning projects..."
    while IFS='|' read -r type proj; do
        case "$type" in
            FLUTTER)
                log "${BLUE}Flutter: $proj${NC}"
                (cd "$proj" && flutter clean >/dev/null 2>&1)
                rm -rf "$proj/build" "$proj/.dart_tool"
                ;;
            RUST)
                log "${BLUE}Rust: $proj${NC}"
                (cd "$proj" && cargo clean >/dev/null 2>&1) || rm -rf "$proj/target"
                ;;
            NODE)
                log "${BLUE}Node: $proj${NC}"
                rm -rf "$proj/node_modules"
                for out in .next .nuxt .output dist .svelte-kit .turbo; do
                    [ -d "$proj/$out" ] && rm -rf "$proj/$out"
                done
                ;;
        esac
    done < "$plan_file"

    after_total=0
    while IFS='|' read -r type proj; do
        paths=$(entry_paths "$type" "$proj")
        after_total=$((after_total + $(path_size_kb $paths)))
    done < "$plan_file"

    rm -f "$plan_file"
    spin_stop
    FREED_KB=$((FREED_KB + before_total - after_total))
    echo -e "${GREEN}Done. Freed: $(human_kb "$((before_total - after_total))")${NC}"
}

# Main menu
while true; do
    echo -e "\n${BLUE}=== Directory Management Tool ===${NC}"
    echo "1. Show all sizes (summary first, details on request)"
    echo ""
    echo "-- macOS --"
    echo "2. Clean Logs and Caches (~/Library/Logs, ~/Library/Caches)"
    echo ""
    echo "-- iOS / Xcode --"
    echo "3. Clean iOS cache (Xcode + CoreSimulator caches)"
    echo "4. Clean iOS build results (DerivedData, Archives)"
    echo "5. Clean iOS simulators (xcrun simctl delete unavailable)"
    echo "6. Clean iOS simulator runtimes [heavy] (pick which iOS versions to delete)"
    echo "7. Clean iOS OS support [heavy] (iOS DeviceSupport)"
    echo "8. Clean simulator dyld cache (pick per runtime, needs sudo)"
    echo ""
    echo "-- Flutter / Android --"
    echo "9. Clean Flutter build results (all Flutter projects under Work/Projects)"
    echo "10. Clean Flutter cache (~/.pub-cache)"
    echo "11. Clean Dart analysis cache (~/.dartServer)"
    echo "12. Remove Flutter SDK versions [heavy] (fvm, pick which versions)"
    echo "13. Clean Gradle (~/.gradle)"
    echo "14. Clean Android emulator images [heavy] (sdk/system-images)"
    echo "15. Clean Android AVDs [heavy] (~/.android/avd)"
    echo "16. Clean Android SDK [heavy] (~/Library/Android/sdk)"
    echo ""
    echo "-- Node --"
    echo "17. Clean node_modules + build outputs (all Node/Next/Nuxt/Vite projects, monorepos too)"
    echo "18. Clean npm cache (npm cache clean --force + npx cache)"
    echo "19. Prune pnpm store (pnpm store prune)"
    echo "20. Clean Puppeteer Chromium cache (~/.cache/puppeteer)"
    echo "21. Remove Node versions [heavy] (nvm, pick which versions)"
    echo ""
    echo "-- Rust / Go --"
    echo "22. Clean Rust target dirs (all Rust projects)"
    echo "23. Clean Cargo registry cache (~/.cargo/registry)"
    echo "24. Clean Go module cache (go clean -modcache)"
    echo ""
    echo "-- Editors --"
    echo "25. Clean editor caches (Devin, Cursor, Windsurf, VS Code; cache folders only, skips a running editor)"
    echo ""
    echo "-- Docker --"
    echo "26. Clean Docker (stops running containers, keeps volumes)"
    echo "27. Clean Docker build cache only (keeps images/containers/volumes)"
    echo ""
    echo "-- Combos --"
    echo "28. Clean ALL light (everything except [heavy] items and the sudo dyld cache)"
    echo "29. Clean EVERYTHING (28 + [heavy] items 7, 15, 16; runtimes and version managers stay out, see 6 and 30)"
    echo "30. Remove versions: Flutter (fvm) then Node (nvm), each one asks which to remove"
    echo ""
    echo "31. Exit"

    read -p "Enter your choice (1-31): " choice

    case $choice in
        1)  show_all_sizes ;;
        2)  clean_macos_caches ;;
        3)  clean_ios_cache ;;
        4)  clean_ios_build ;;
        5)  clean_simulators ;;
        6)  clean_ios_runtimes ;;
        7)  clean_dir ~/Library/Developer/Xcode/iOS\ DeviceSupport ;;
        8)  clean_sim_dyld_cache ;;
        9)  clean_all_projects FLUTTER ;;
        10) clean_dir ~/.pub-cache ;;
        11) clean_dir ~/.dartServer ;;
        12) fvm_remove_versions ;;
        13) clean_dir ~/.gradle ;;
        14) clean_dir ~/Library/Android/sdk/system-images ;;
        15) clean_dir ~/.android/avd ;;
        16) clean_dir ~/Library/Android/sdk ;;
        17) clean_all_projects NODE ;;
        18) clean_npm_cache ;;
        19) clean_pnpm_store ;;
        20) clean_dir ~/.cache/puppeteer ;;
        21) nvm_remove_versions ;;
        22) clean_all_projects RUST ;;
        23) clean_cargo_registry ;;
        24) clean_go_modcache ;;
        25) clean_ide_caches ;;
        26) clean_docker ;;
        27) clean_docker_cache ;;
        28) clean_light ;;
        29) clean_light; clean_heavy ;;
        30) fvm_remove_versions; nvm_remove_versions ;;
        31)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    esac

    offer_log
done
