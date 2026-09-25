#!/usr/bin/env bash
# Host setup for running Claude Code in Docker Sandboxes (sbx).
# Safe to re-run. Existing ~/.sbxenv.yaml and kit files are moved to *.bak.<timestamp>.
#
# Usage:
#   ./setup.sh          configure sbx and install ~/.sbxenv.yaml + kit
#   ./setup.sh --print  only print the generated ~/.sbxenv.yaml (changes nothing)
#
# Overrides (environment variables):
#   SBX_POLICY           network policy preset for first-time init: deny-all | balanced | allow-all (default deny-all)
#   SBX_ALLOWED_SOURCES  JSON list for kit.allowedSources (default: docker.io + github.com/docker)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
KIT_DIR="$HOME/.sbx-kits/claude-safe"
ENV_FILE="$HOME/.sbxenv.yaml"
SBX_POLICY="${SBX_POLICY:-deny-all}"
SBX_ALLOWED_SOURCES="${SBX_ALLOWED_SOURCES:-[\"docker.io/\",\"github.com/docker/\"]}"
TS="$(date +%Y%m%d%H%M%S)"

# Paths below ~/.claude that must not change from inside a sandbox. Only
# entries that exist are mounted, because sbx fails on a missing mount path.
RO_DIRS="skills plugins rules agents commands output-styles"
RO_FILES="settings.json CLAUDE.md"

# Claude Code state directories: large, never hold config, skip when scanning.
PRUNE_DIRS="plugins projects debug file-history shell-snapshots session-env todos statsig cache"

resolve() { realpath "$1" 2>/dev/null || true; }

rel_to_home() {
  case "$1" in
    "$HOME"/*) printf './%s\n' "${1#"$HOME"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Directory to mount so that a symlink target resolves inside the sandbox.
# Uses the git repo root when the target is in a repo, so one mount covers
# every link into a dotfiles repo. Never returns $HOME itself.
mount_root() {
  local target="$1" dir top
  if [ -d "$target" ]; then dir="$target"; else dir="$(dirname "$target")"; fi
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ] && [ "$top" != "$HOME" ]; then printf '%s\n' "$top"; else printf '%s\n' "$dir"; fi
}

# sbx fails to start the sandbox container when a mounted directory holds a
# symlink whose target is outside every mount. This finds those targets.
# Prints "BROKEN <link>" or "ROOT <dir>" lines.
scan_links() {
  local prune=() d link target
  for d in $PRUNE_DIRS; do prune+=(-path "$CLAUDE_DIR/$d" -prune -o); done
  find "$CLAUDE_DIR" "${prune[@]}" -type l -print 2>/dev/null | while read -r link; do
    target="$(resolve "$link")"
    if [ -z "$target" ] || [ ! -e "$target" ]; then
      echo "BROKEN $link"
    else
      case "$target" in
        "$CLAUDE_DIR"/*) ;;
        *) echo "ROOT $(mount_root "$target")" ;;
      esac
    fi
  done
}

render_env() {
  local links roots name last=""
  cat "$REPO_DIR/sbxenv.yaml"

  for name in $RO_DIRS; do
    [ -d "$CLAUDE_DIR/$name" ] && printf '  - path: ./.claude/%s\n    readOnly: true\n' "$name"
  done
  # A single-file mount only works on a real file. A symlinked file stays
  # read-only through the mount of its target (added below).
  for name in $RO_FILES; do
    [ -f "$CLAUDE_DIR/$name" ] && [ ! -L "$CLAUDE_DIR/$name" ] &&
      printf '  - path: ./.claude/%s\n    readOnly: true\n' "$name"
  done

  links="$(scan_links)"
  roots="$(printf '%s\n' "$links" | sed -n 's/^ROOT //p' | sort -u)"
  if [ -n "$roots" ]; then
    echo
    echo "  # Symlink targets outside ~/.claude (found by setup.sh). Mounted"
    echo "  # read-only so the links resolve and writes through them fail."
    while read -r name; do
      # Skip a root that sits inside the previous one (sort puts parents first).
      if [ -n "$last" ] && case "$name" in "$last"/*) true ;; *) false ;; esac; then continue; fi
      printf '  - path: %s\n    readOnly: true\n' "$(rel_to_home "$name")"
      last="$name"
    done <<< "$roots"
  fi
}

report_broken() {
  local broken
  broken="$(scan_links | sed -n 's/^BROKEN //p')"
  if [ -n "$broken" ]; then
    echo
    echo "WARNING: broken symlinks in $CLAUDE_DIR. They can stop the sandbox from starting."
    echo "Remove or fix them, then re-run ./setup.sh:"
    printf '  %s\n' $broken
  fi
}

# Moves an existing file or symlink aside instead of writing through it.
backup() {
  if [ -e "$1" ] || [ -L "$1" ]; then mv "$1" "$1.bak.$TS"; echo "Backed up $1 -> $1.bak.$TS"; fi
}

if [ "${1:-}" = "--print" ]; then
  render_env
  report_broken >&2
  exit 0
fi

if ! command -v sbx >/dev/null 2>&1; then
  echo "sbx not found. Install Docker Sandboxes first (macOS: brew install --cask docker/tap/sbx)."
  exit 1
fi
if [ ! -d "$CLAUDE_DIR" ]; then
  echo "$CLAUDE_DIR not found. Run Claude Code on the host once, then re-run this script."
  exit 1
fi

echo "==> Kit sources"
# This setting replaces the whole list. Add any sources you already allow.
sbx settings set kit.allowedSources "$SBX_ALLOWED_SOURCES"

echo "==> Network policy"
# `sbx policy init` only works before a preset exists. On a re-run it fails,
# and the existing preset stays.
sbx policy init "$SBX_POLICY" || echo "Policy already initialized. Skipped."

echo "==> GitHub credential"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  sbx secret set github --command 'gh auth token'
else
  echo "gh not installed or not logged in. Skipped. Run 'gh auth login', then re-run."
fi

echo "==> Kit: $KIT_DIR"
mkdir -p "$KIT_DIR"
backup "$KIT_DIR/spec.yaml"
sed "s|__HOME__|$HOME|g" "$REPO_DIR/kit/claude-safe/spec.yaml" > "$KIT_DIR/spec.yaml"

echo "==> Environment file: $ENV_FILE"
new_env="$(render_env)"
backup "$ENV_FILE"
printf '%s\n' "$new_env" > "$ENV_FILE"

report_broken
echo
echo "Done. In a project directory, run: sbx env run"
