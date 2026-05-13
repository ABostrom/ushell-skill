#!/bin/bash
# Mode B helper for live-streaming ushell output to Claude Code conversations.
#
# Usage:
#   ./tests/stream-ushell.sh <project-uproject> <verb-and-args...>
#
# Example:
#   ./tests/stream-ushell.sh \
#       E:/Work/Games/ProjectGear/ProjectGear.uproject \
#       '.build editor --nosummary'
#
# Writes a sentinel-bracketed log to /tmp/ushell-stream.log. Pair with a
# Monitor that tails the log with line-buffered grep for the same markers
# documented in reference/invocation.md "Live output streaming".

set -o pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <project-uproject-path> <ushell-verb-and-args>" >&2
    echo "" >&2
    echo "After dispatching this via Bash run_in_background:true, run a Monitor:" >&2
    echo "" >&2
    echo "  tail -F /tmp/ushell-stream.log 2>/dev/null | \\" >&2
    echo "    stdbuf -oL grep -E 'STREAM_(BEGIN|END)|\\[[0-9]+/[0-9]+\\]|Result: Succeeded|Result: Failed|^== Run:|error C[0-9]+:|fatal error|ERROR:|Exception while|Plugin .* dependency' | \\" >&2
    echo "    while IFS= read -r line; do" >&2
    echo "      printf '%s\\n' \"\$line\"" >&2
    echo "      if [[ \"\$line\" == STREAM_END* ]]; then exit 0; fi" >&2
    echo "    done" >&2
    exit 64
fi

UPROJECT="$1"
shift
USHELL_ARGS="$*"
LOG="${USHELL_STREAM_LOG:-/tmp/ushell-stream.log}"

# Discover ushell.bat — walks up from <uproject>'s parent dir looking for Engine/Extras/ushell/ushell.bat,
# OR falls back to USHELL_BAT env var, OR the default UE 5.7 install location.
locate_ushell() {
    # Convert /e/... bash paths to E:/ Windows paths for the search.
    local dir
    dir="$(cygpath -w "$(dirname "$UPROJECT")" 2>/dev/null)" || dir="$(dirname "$UPROJECT")"
    while [[ -n "$dir" && "$dir" != "/" && "$dir" != "C:\\" ]]; do
        local candidate="${dir}\\Engine\\Extras\\ushell\\ushell.bat"
        if [[ -f "$(cygpath -u "$candidate" 2>/dev/null || echo "$candidate")" ]]; then
            echo "$candidate"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    if [[ -n "${USHELL_BAT:-}" && -f "$USHELL_BAT" ]]; then
        echo "$USHELL_BAT"
        return 0
    fi
    if [[ -f "/e/UE_5.7/Engine/Extras/ushell/ushell.bat" ]]; then
        echo "E:\\UE_5.7\\Engine\\Extras\\ushell\\ushell.bat"
        return 0
    fi
    return 1
}

USHELL_BAT_PATH="$(locate_ushell)" || {
    echo "ERROR: couldn't locate ushell.bat. Set USHELL_BAT env var to its full Windows path." >&2
    exit 1
}

rm -f "$LOG"
echo "STREAM_BEGIN ushell=$USHELL_BAT_PATH project=$UPROJECT verb=$USHELL_ARGS ts=$(date +%s)" > "$LOG"

# Convert /e/... project path to Windows form for cmd.exe.
PROJECT_WIN="$(cygpath -w "$UPROJECT" 2>/dev/null || echo "$UPROJECT")"

MSYS_NO_PATHCONV=1 cmd.exe /d /s /c \
    "call \"$USHELL_BAT_PATH\" --project=\"$PROJECT_WIN\" && $USHELL_ARGS" \
    >> "$LOG" 2>&1
EC=$?

echo "STREAM_END exit_code=$EC ts=$(date +%s)" >> "$LOG"
exit $EC
