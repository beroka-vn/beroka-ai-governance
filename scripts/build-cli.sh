#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
OUTPUT=$ROOT/bin/beroka-governance
MODULES='
src/00-runtime.sh
src/10-repository.sh
src/20-release.sh
src/30-clients.sh
src/40-governance.sh
src/50-cursor-hooks.sh
src/55-confluence-hooks.sh
src/90-main.sh
'

case "${1:-}" in
  '') mode=write ;;
  --check) mode=check ;;
  *)
    printf '%s\n' 'Usage: scripts/build-cli.sh [--check]' >&2
    exit 2
    ;;
esac
[ "$#" -le 1 ] || {
  printf '%s\n' 'Usage: scripts/build-cli.sh [--check]' >&2
  exit 2
}

temporary=$(mktemp "$ROOT/bin/.beroka-governance.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
: >"$temporary"
first=1
for relative in $MODULES; do
  module=$ROOT/$relative
  [ -f "$module" ] || {
    printf '%s\n' "Missing CLI module: $relative" >&2
    exit 1
  }
  if [ "$first" -eq 0 ]; then printf '\n' >>"$temporary"; fi
  first=0
  cat "$module" >>"$temporary"
done

sh -n "$temporary"
chmod 755 "$temporary"
if [ "$mode" = check ]; then
  if ! cmp -s "$temporary" "$OUTPUT"; then
    printf '%s\n' 'Generated CLI is stale. Run: scripts/build-cli.sh' >&2
    exit 1
  fi
  exit 0
fi
mv "$temporary" "$OUTPUT"
trap - EXIT HUP INT TERM
