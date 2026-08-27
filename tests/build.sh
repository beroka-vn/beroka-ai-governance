#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-build-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

[ -x "$ROOT/scripts/build-cli.sh" ] ||
  fail 'build script is not executable'
"$ROOT/scripts/build-cli.sh" --check ||
  fail 'committed CLI is stale'

mkdir -p "$TMP_ROOT/repo"
cp -R "$ROOT/src" "$ROOT/scripts" "$ROOT/bin" "$TMP_ROOT/repo/"
builder=$TMP_ROOT/repo/scripts/build-cli.sh
artifact=$TMP_ROOT/repo/bin/beroka-governance

"$builder"
first_checksum=$(cksum "$artifact")
"$builder"
[ "$first_checksum" = "$(cksum "$artifact")" ] ||
  fail 'two builds produced different artifacts'
"$builder" --check || fail 'fresh artifact failed --check'

printf '%s\n' '# stale source mutation' >>"$TMP_ROOT/repo/src/00-runtime.sh"
if "$builder" --check >/dev/null 2>&1; then
  fail '--check accepted a stale artifact'
fi
"$builder"
"$builder" --check || fail 'rebuilt artifact failed --check'

good_checksum=$(cksum "$artifact")
printf '%s\n' 'if then' >>"$TMP_ROOT/repo/src/50-cursor-hooks.sh"
if "$builder" >/dev/null 2>&1; then
  fail 'builder accepted malformed shell'
fi
[ "$good_checksum" = "$(cksum "$artifact")" ] ||
  fail 'failed build replaced the last valid artifact'

printf '%s\n' 'Modular CLI build tests: PASS'
