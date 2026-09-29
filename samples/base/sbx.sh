#!/usr/bin/env bash
# Build the Docker Sandboxes template for this project and start the sandbox.
#
# Usage:
#   ./sbx.sh [run]     build the template if sbx does not have it, then start or attach to the sandbox
#   ./sbx.sh build     build the template, and load it into sbx if the image changed
#   ./sbx.sh rebuild   build without the Docker cache (gets a new uv and new apt packages), then load it
#   ./sbx.sh recreate  remove the sandbox, then create and start it again
#
# A running sandbox keeps its old template, kit, and sbxenv.yaml. After a change to one of them, run recreate.
# Recreate removes the sandbox venv (.venv-sbx stays on disk) but not Claude Code sessions, which live in ~/.claude.
#
# Needs Docker Desktop and ~/.sbxenv.yaml from docker-sbx-poc/setup.sh.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="$(sed -n 's/^ *template: *//p' sbxenv.yaml)"
# sbx names the sandbox <agent>-<directory>. ~/.sbxenv.yaml sets the agent.
SANDBOX="claude-safe-$(basename "$PWD")"

docker_id() {
  docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null | cut -d: -f2 | cut -c1-12
}

# sbx keeps its own image store, apart from Docker, and lists local images under docker.io/.
template_id() {
  sbx template ls 2>/dev/null |
    awk -v repo="docker.io/${IMAGE%:*}" -v tag="${IMAGE##*:}" '$1 == repo && $2 == tag { print $3 }'
}

sandbox_exists() {
  sbx ls 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -qx "$SANDBOX"
}

build() {
  # Provenance data holds a build time, so without this flag each build gets a new image ID, and the check below
  # always finds a change.
  docker build --provenance=false "$@" -t "$IMAGE" - < Dockerfile.sbx

  if [ "$(docker_id)" = "$(template_id)" ]; then
    echo "sbx already has this template."
    return
  fi

  local tar="$(mktemp -t sbx-template.XXXXXX)"
  trap 'rm -f "$tar"' RETURN
  docker image save "$IMAGE" -o "$tar"
  sbx template load "$tar"

  if sandbox_exists; then
    echo "Template changed. Run './sbx.sh recreate' to use it in $SANDBOX."
  fi
}

run() {
  [ -n "$(template_id)" ] || build
  sbx env run
}

recreate() {
  [ -n "$(template_id)" ] || build
  if sandbox_exists; then
    sbx rm "$SANDBOX"
  fi
  sbx env run
}

case "${1:-run}" in
  run) run ;;
  build) build ;;
  rebuild) build --no-cache ;;
  recreate) recreate ;;
  *)
    sed -n '4,8p' "$0" | sed 's/^# //'
    exit 1
    ;;
esac
