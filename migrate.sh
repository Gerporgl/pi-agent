#!/usr/bin/env bash
#
# migrate.sh — migrate pi / pi-web state stored under /home/ubuntu to /home/agent.
#
# Usage: ./migrate.sh <home-folder> [--dry-run]
#
# <home-folder> is the root of a pi-agent home (the folder bind-mounted as the
# container's /home/agent), e.g. ./pi-agent-home. It must contain a .pi/ and/or
# .pi-web/ directory.
#
# What it does:
#   1. Renames pi session directories under .pi/agent/sessions/ from
#      --home-ubuntu-<path>-- to --home-agent-<path>--. (pi encodes each
#      session's cwd into the directory name, e.g. /home/ubuntu/sandbox is
#      stored in .pi/agent/sessions/--home-ubuntu-sandbox--.)
#   2. Rewrites /home/ubuntu -> /home/agent (and the encoded form
#      --home-ubuntu- -> --home-agent-) in the small pi / pi-web state files:
#        .pi/agent/trust.json
#        .pi-web/projects.json
#        .pi-web/archived-sessions.json
#        .pi-web/session-unread.json
#        .pi-web/sessiond-owner.json
#   3. Does NOT touch session discussion files (*.jsonl): neither the files
#      under .pi/agent/sessions/**/ nor .pi-web/archived-sessions/*.jsonl.
#
# Workspaces do not need separate handling: pi-web derives them at runtime from
# the project paths in .pi-web/projects.json (project root + git worktrees).
#
# Safety: refuses to run against the agent's own live home ($HOME / /home/agent),
# the filesystem root, or any folder that does not contain .pi or .pi-web.

set -euo pipefail

OLD_HOME="/home/ubuntu"
NEW_HOME="/home/agent"
OLD_SAFE="--home-ubuntu-"
NEW_SAFE="--home-agent-"

usage() {
    echo "Usage: $(basename "$0") <home-folder> [--dry-run]" >&2
}

DRY_RUN=0
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        -*)
            echo "Unknown option: $arg" >&2
            usage
            exit 2
            ;;
        *)
            if [ -n "$TARGET" ]; then
                echo "Only one home folder argument is allowed." >&2
                usage
                exit 2
            fi
            TARGET="$arg"
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    usage
    exit 2
fi

if [ ! -d "$TARGET" ]; then
    echo "Error: '$TARGET' is not a directory." >&2
    exit 1
fi

TARGET="$(realpath "$TARGET")"

# Refuse to migrate the agent's own live home or the filesystem root.
if [ "$TARGET" = "/" ] || [ "$TARGET" = "$HOME" ] || [ "$TARGET" = "/home/agent" ]; then
    echo "Error: refusing to migrate '$TARGET' — it is the agent's own home." >&2
    exit 1
fi

# The folder must actually be a pi-agent home.
if [ ! -d "$TARGET/.pi" ] && [ ! -d "$TARGET/.pi-web" ]; then
    echo "Error: '$TARGET' contains no .pi or .pi-web directory." >&2
    echo "       Pass the folder that is bind-mounted as the container's /home/agent." >&2
    exit 1
fi

MODE="apply"
[ "$DRY_RUN" = 1 ] && MODE="dry-run"

echo "pi / pi-web home migration: ${OLD_HOME} -> ${NEW_HOME}"
echo "Target: $TARGET"
echo "Mode:   $MODE"
echo

# --- 1) Rename session directories under .pi/agent/sessions/ ---------------

RENAMED=()
SESSIONS_DIR="$TARGET/.pi/agent/sessions"
if [ -d "$SESSIONS_DIR" ]; then
    for dir in "$SESSIONS_DIR"/"$OLD_SAFE"*; do
        [ -d "$dir" ] || continue
        base="$(basename "$dir")"
        newname="${base/"$OLD_SAFE"/"$NEW_SAFE"}"
        dest="$SESSIONS_DIR/$newname"
        if [ -e "$dest" ]; then
            echo "Error: $dest already exists; refusing to overwrite." >&2
            exit 1
        fi
        if [ "$DRY_RUN" = 0 ]; then
            mv "$dir" "$dest"
        fi
        RENAMED+=("$base -> $newname")
    done
fi

echo "Session directories renamed: ${#RENAMED[@]}"
for line in "${RENAMED[@]:-}"; do
    [ -n "$line" ] && echo "  $line"
done
echo

# --- 2) Rewrite paths in the small state files ------------------------------

STATE_FILES=(
    ".pi/agent/trust.json"
    ".pi-web/projects.json"
    ".pi-web/archived-sessions.json"
    ".pi-web/session-unread.json"
    ".pi-web/sessiond-owner.json"
)

UPDATED=()
CLEAN=()
for rel in "${STATE_FILES[@]}"; do
    f="$TARGET/$rel"
    [ -f "$f" ] || continue
    if grep -q -e "$OLD_HOME" -e "$OLD_SAFE" "$f"; then
        if [ "$DRY_RUN" = 0 ]; then
            sed -i -e "s|$OLD_HOME|$NEW_HOME|g" -e "s|$OLD_SAFE|$NEW_SAFE|g" "$f"
        fi
        UPDATED+=("$rel")
    else
        CLEAN+=("$rel")
    fi
done

echo "State files updated: ${#UPDATED[@]}"
for rel in "${UPDATED[@]:-}"; do
    [ -n "$rel" ] && echo "  $rel"
done
echo
echo "State files already clean (no old paths): ${#CLEAN[@]}"
for rel in "${CLEAN[@]:-}"; do
    [ -n "$rel" ] && echo "  $rel"
done
echo

# --- 3) Verification: what old references remain ----------------------------

echo "Remaining '$OLD_HOME' references outside *.jsonl:"
LEFTOVER="$(grep -r -l -e "$OLD_HOME" -e "$OLD_SAFE" "$TARGET" \
    --exclude='*.jsonl' 2>/dev/null || true)"
if [ -n "$LEFTOVER" ]; then
    echo "$LEFTOVER" | sed 's|^|  |'
else
    echo "  (none)"
fi
echo
echo "Note: *.jsonl session discussion files were intentionally left untouched."
echo "      Their first line (session header) still records the old cwd; pi-web"
echo "      may show such sessions under the old path, but they remain loadable."
echo

if [ "$DRY_RUN" = 1 ]; then
    echo "Dry run complete — nothing was changed."
else
    echo "Migration complete."
fi
