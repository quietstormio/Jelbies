#!/bin/bash
# cleanup-safe.sh - reclaim disk space safely (build caches, agent simulators,
# stale worktrees, scratch copies). DRY RUN by default; deletes only with --apply.
# Needs only git, xcrun, du, awk (bash 3.2 compatible).
#
# Usage: scripts/cleanup-safe.sh [--apply] [--yes] [--keep-dev-hours N] [--all-sims]
#                                [--protect NAME]... [--min-free-gb N] [--only TEXT]
set -u

ONLY=""; APPLY=0; YES=0; KEEP_DEV_HOURS=6; ALL_SIMS=0; MIN_FREE_GB=20
PROTECT_LIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --yes) YES=1 ;;
    --keep-dev-hours) KEEP_DEV_HOURS="$2"; shift ;;
    --all-sims) ALL_SIMS=1 ;;
    --protect) PROTECT_LIST="$PROTECT_LIST
$2"; shift ;;
    --min-free-gb) MIN_FREE_GB="$2"; shift ;;
    --only) ONLY="$2"; shift ;;   # restrict report/apply to items whose label contains this text (testing)
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
THIS_TOP="$(git -C "$SELF_DIR" rev-parse --show-toplevel)"
# main worktree = first entry of the worktree list
MAIN_WT="$(git -C "$THIS_TOP" worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')"
WT_DIR="$MAIN_WT/.claude/worktrees"
SCRATCH_GLOB="/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/*/scratchpad"
DATA_VOL=/System/Volumes/Data
NOW=$(date +%s)

# never-delete roots (rule f)
PROTECTED_PATHS="$HOME/BobV1_backups
$MAIN_WT
$MAIN_WT/.git
$HOME/.config
$HOME/.claude/projects"

ITEMS="$(mktemp -t cleanup-items)"   # verdict|kind|target|kb|label|note
trap 'rm -f "$ITEMS"' EXIT

kb_of() { du -sk "$1" 2>/dev/null | awk '{print $1+0}'; }
ACTIVE_MIN=30   # anything written in the last N minutes may be a live build: keep it
add() {
  local v="$1" n="$6"
  case "$2" in dd|xcdd|scratch)
    if [ "$v" = SAFE ] && [ -n "$(find "$3" -mmin -$ACTIVE_MIN -print -quit 2>/dev/null)" ]; then
      v=PROTECTED; n="written in last ${ACTIVE_MIN} min (live build?)"
    fi ;;
  esac
  printf '%s|%s|%s|%s|%s|%s\n' "$v" "$2" "$3" "$4" "$5" "$n" >> "$ITEMS"
}
mtime_of() { stat -f %m "$1" 2>/dev/null || echo 0; }

# a path may be deleted only if it is not (inside/equal to) a protected path
is_protected_path() {
  local p="$1" q
  while IFS= read -r q; do
    [ -z "$q" ] && continue
    [ "$p" = "$q" ] && return 0
    case "$p" in "$q"/*) [ "$q" != "$MAIN_WT" ] && return 0 ;; esac
  done <<EOF2
$PROTECTED_PATHS
EOF2
  # the main working tree itself and its .git, or any ancestor of them
  case "$MAIN_WT" in "$p"/*) return 0 ;; esac
  return 1
}

is_user_protected() {
  local n="$1" p="$2" q
  while IFS= read -r q; do
    [ -z "$q" ] && continue
    [ "$q" = "$n" ] || [ "$q" = "$p" ] && return 0
  done <<EOF2
$PROTECT_LIST
EOF2
  return 1
}

# ---- a. dd_* derived data in worktrees dir ----
for d in "$WT_DIR"/dd_*; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"; kb="$(kb_of "$d")"
  case "$name" in
    dd_*_dev)
      app="$d/Build/Products/Release-iphoneos/BobV1.app"
      if [ -e "$app" ]; then
        m=$(mtime_of "$app"); age=$(( (NOW - m) / 3600 ))
        ts="$(date -r "$m" '+%Y-%m-%d %H:%M')"
        if [ "$age" -lt "$KEEP_DEV_HOURS" ]; then
          add PROTECTED dd "$d" "$kb" "$name" "dev build ${age}h old (< ${KEEP_DEV_HOURS}h), may be un-installed; BobV1.app mtime $ts"
          continue
        fi
        add SAFE dd "$d" "$kb" "$name" "regenerable; dev BobV1.app mtime $ts (${age}h old)"
        continue
      fi ;;
  esac
  add SAFE dd "$d" "$kb" "$name" "regenerable derived data"
done

# ---- b. Xcode DerivedData ----
for d in "$HOME/Library/Developer/Xcode/DerivedData"/*; do
  [ -e "$d" ] || continue
  add SAFE xcdd "$d" "$(kb_of "$d")" "DerivedData/$(basename "$d")" "regenerable derived data"
done

# ---- c. simulators ----
if command -v xcrun >/dev/null 2>&1; then
  xcrun simctl list devices -j 2>/dev/null | awk '
    /"udid"/  { gsub(/.*: "|",?$/,""); u=$0 }
    /"state"/ { gsub(/.*: "|",?$/,""); s=$0 }
    /"name"/  { gsub(/.*: "|",?$/,""); n=$0 }
    /^ *}/    { if (u!="") print u "\t" s "\t" n; u=""; s=""; n="" }
  ' | while IFS="$(printf '\t')" read -r udid state name; do
    dp="$HOME/Library/Developer/CoreSimulator/Devices/$udid"
    kb=0; [ -d "$dp" ] && kb="$(kb_of "$dp")"
    match=0
    case "$name" in
      *-sim|*-test*|r10*|gpubody*|newgame*|feetdiag*|onepiece*|scenes*|perf*|fx-*) match=1 ;;
    esac
    if [ "$match" = 0 ] && [ "$ALL_SIMS" = 0 ]; then
      add PROTECTED sim "$udid" "$kb" "sim $name" "not an agent-pattern name (user's own), $state"
    elif [ "$state" = "Booted" ] && [ "$ALL_SIMS" = 0 ]; then
      add PROTECTED sim "$udid" "$kb" "sim $name" "Booted (use --all-sims to override)"
    else
      add SAFE sim "$udid" "$kb" "sim $name" "agent simulator, $state"
    fi
  done
fi

# ---- d. worktrees ----
all_other_refs() {  # refs except $1
  git -C "$MAIN_WT" for-each-ref --format='%(refname)' refs/heads refs/remotes | grep -vxF "$1"
}
git -C "$MAIN_WT" worktree list --porcelain | awk '
  /^worktree /{ if (p!="") print p "\t" (b==""?"-":b) "\t" h "\t" (d==""?"-":d); p=substr($0,10); b=""; h=""; d="" }
  /^HEAD /{ h=substr($0,6) }
  /^branch /{ b=substr($0,8) }
  /^detached/{ d="1" }
  END{ if (p!="") print p "\t" (b==""?"-":b) "\t" h "\t" (d==""?"-":d) }
' > "$ITEMS.wt"
first=1
while IFS="$(printf '\t')" read -r wpath wbranch whead wdet; do
  if [ "$first" = 1 ]; then first=0; continue; fi   # main worktree
  name="$(basename "$wpath")"
  [ -d "$wpath" ] || { add PROTECTED wt "$wpath" 0 "worktree $name" "directory missing (git worktree prune handles it)"; continue; }
  kb="$(kb_of "$wpath")"
  [ "$wbranch" = "-" ] && wbranch=""
  short="${wbranch#refs/heads/}"
  if [ "$wpath" = "$MAIN_WT" ] || [ "$wpath" = "$THIS_TOP" ]; then
    add PROTECTED wt "$wpath" "$kb" "worktree $name" "main / running worktree"; continue; fi
  if [ "$short" = "g-int" ] || [ "$name" = "g-int" ]; then
    add PROTECTED wt "$wpath" "$kb" "worktree $name" "g-int is never touched"; continue; fi
  if is_user_protected "$name" "$wpath"; then
    add PROTECTED wt "$wpath" "$kb" "worktree $name" "listed in --protect"; continue; fi
  case "$name" in
    *-base|g-r*_[a-z]|agent-*) ;;
    *) add PROTECTED wt "$wpath" "$kb" "worktree $name" "name is not a throwaway pattern (*-base, g-r*_[a-z], agent-*)"; continue ;;
  esac
  dirty="$(git -C "$wpath" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$dirty" != 0 ]; then
    add PROTECTED wt "$wpath" "$kb" "worktree $name" "dirty ($dirty uncommitted/untracked entries)"; continue; fi
  if [ -n "$wbranch" ]; then
    others="$(all_other_refs "$wbranch" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    n="$(git -C "$MAIN_WT" rev-list --count "$wbranch" --not $others 2>/dev/null || echo 999)"
    if [ "$n" != 0 ]; then
      add PROTECTED wt "$wpath" "$kb" "worktree $name" "$n unmerged commits on $short"; continue; fi
    add SAFE wt "$wpath" "$kb" "worktree $name" "branch $short fully contained in other branches, clean (branch kept)"
  else
    ok=0
    for r in g-int main release-1.0; do
      git -C "$MAIN_WT" rev-parse -q --verify "$r" >/dev/null 2>&1 || continue
      git -C "$MAIN_WT" merge-base --is-ancestor "$whead" "$r" 2>/dev/null && { ok=1; break; }
    done
    if [ "$ok" = 1 ]; then
      add SAFE wt "$wpath" "$kb" "worktree $name" "detached at ${whead:0:8}, reachable from g-int/main/release-1.0, clean"
    else
      add PROTECTED wt "$wpath" "$kb" "worktree $name" "detached at ${whead:0:8}, NOT reachable from g-int/main/release-1.0"
    fi
  fi
done < "$ITEMS.wt"
rm -f "$ITEMS.wt"

# ---- e. scratchpad ----
for sp in $SCRATCH_GLOB; do
  [ -d "$sp" ] || continue
  for d in "$sp"/* "$sp"/*/*; do
    [ -d "$d" ] || continue
    [ -L "$d" ] && continue
    rel="${d#$sp/}"; base="$(basename "$d")"
    # skip children of something already listed
    case "$rel" in */*) parent="$sp/${rel%%/*}"
      if grep -qF "|$parent|" "$ITEMS" 2>/dev/null; then continue; fi ;; esac
    why=""
    case "$base" in
      src|hoptick|dd_*|*.trace) why="scratch build/trace folder ($base)" ;;
    esac
    if [ -z "$why" ] && [ -e "$d/BobV1.xcodeproj" ]; then
      k="$(kb_of "$d")"
      [ "$k" -gt 512000 ] && why="repo copy over 500 MB"
    fi
    case "$rel" in */*) [ -z "$why" ] && continue ;; esac   # only list depth-2 when deletable
    k="$(kb_of "$d")"
    if [ -n "$why" ]; then add SAFE scratch "$d" "$k" "scratch/$rel" "$why"
    else add PROTECTED scratch "$d" "$k" "scratch/$rel" "may hold captures/boards the user is shown"; fi
  done
done

# ---- f. always-protected, shown for visibility (never deletable) ----
for p in "$HOME/BobV1_backups" "$HOME/.claude/projects" "$HOME/.config"; do
  [ -e "$p" ] && add PROTECTED fixed "$p" "$(kb_of "$p")" "$p" "ALWAYS protected"
done
add PROTECTED fixed "$MAIN_WT" 0 "repo working tree + .git" "ALWAYS protected"

# ---- report ----
if [ -n "$ONLY" ]; then grep -F "|$ONLY" "$ITEMS" > "$ITEMS.o"; mv "$ITEMS.o" "$ITEMS"; fi
human() { awk -v k="$1" 'BEGIN{ if(k>=1048576) printf "%.1f GB",k/1048576; else if(k>=1024) printf "%.0f MB",k/1024; else printf "%d KB",k }'; }
total=$(awk -F'|' '$1=="SAFE"{s+=$4} END{print s+0}' "$ITEMS")
echo "Disk (before): $(df -h $DATA_VOL | tail -1 | awk '{print $4 " free of " $2 " (" $5 " used)"}')"
echo "Mode: $([ $APPLY = 1 ] && echo APPLY || echo 'DRY RUN (nothing is deleted; pass --apply)')"
echo
printf '%-10s %-5s %10s  %-34s %s\n' VERDICT KIND SIZE ITEM NOTE
sort -t'|' -k1,1r -k4,4nr "$ITEMS" | while IFS='|' read -r v kind target kb label note; do
  printf '%-10s %-5s %10s  %-34s %s\n' "$v" "$kind" "$(human "$kb")" "$label" "$note"
done
echo
echo "Total reclaimable (SAFE): $(human "$total")"

[ "$APPLY" = 1 ] || exit 0

if [ "$YES" = 0 ]; then
  printf 'Delete all SAFE items above? [y/N] '
  read -r ans
  case "$ans" in y|Y|yes) ;; *) echo "aborted"; exit 1 ;; esac
fi

before_free=$(df -k $DATA_VOL | tail -1 | awk '{print $4}')
echo "df before:"; df -h $DATA_VOL
grep '^SAFE|' "$ITEMS" | while IFS='|' read -r v kind target kb label note; do
  case "$kind" in
    sim) xcrun simctl delete "$target" && echo "deleted $label" ;;
    wt)
      if is_protected_path "$target"; then echo "REFUSED $target"; continue; fi
      git -C "$MAIN_WT" worktree remove "$target" && echo "removed $label" ;;   # no --force: refuses if dirty
    *)
      if is_protected_path "$target" || [ -z "$target" ] || [ "$target" = "/" ]; then echo "REFUSED $target"; continue; fi
      rm -rf "$target" && echo "deleted $label" ;;
  esac
done
git -C "$MAIN_WT" worktree prune
echo "df after:"; df -h $DATA_VOL
after_free=$(df -k $DATA_VOL | tail -1 | awk '{print $4}')
echo "Freed: $(awk -v a="$before_free" -v b="$after_free" 'BEGIN{printf "%.2f GB",(b-a)/1048576}')"

free_gb=$(( after_free / 1048576 ))
if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
  echo
  echo "STILL UNDER ${MIN_FREE_GB} GB free (${free_gb} GB). Biggest remaining:"
  for p in "$HOME/Library/Developer" "$HOME/Library/Caches" /private/tmp/claude-501; do
    echo "== $p"; du -sh "$p"/* 2>/dev/null | sort -rh | head -10
  done
  exit 1
fi
exit 0
