#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEMPLATE=$ROOT/release/bootstrap.sh.in
TEST_ROOT=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-launcher-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export HOME=$TEST_ROOT/home
export XDG_CONFIG_HOME=$TEST_ROOT/config
export XDG_DATA_HOME=$TEST_ROOT/data
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected [$2] in [$1]" ;;
  esac
}

source_repo=$TEST_ROOT/source
target_repo=$TEST_ROOT/target
calls=$TEST_ROOT/calls
mkdir -p "$source_repo/bin" "$target_repo"

cat >"$source_repo/bin/beroka-governance" <<EOF
#!/bin/sh
set -eu
printf '%s\n' "\$*" >>"$calls"
case "\$*" in
  *--non-interactive*) printf '%s\n' 'LAUNCHER_NON_INTERACTIVE=PASS' ;;
  *)
    [ -t 0 ] || {
      printf '%s\n' 'Result: TTY_REQUIRED' >&2
      exit 1
    }
    printf '%s\n' 'LAUNCHER_INTERACTIVE=PASS'
    ;;
esac
EOF
chmod 755 "$source_repo/bin/beroka-governance"
printf '%s\n' v9.9.9 >"$source_repo/VERSION"
git -C "$source_repo" init -q
git -C "$source_repo" config user.name launcher-test
git -C "$source_repo" config user.email launcher@example.invalid
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: launcher source'
git -C "$source_repo" tag -a v9.9.9 -m v9.9.9
release_commit=$(git -C "$source_repo" rev-parse 'v9.9.9^{commit}')

git -C "$target_repo" init -q
git -C "$target_repo" config user.name launcher-test
git -C "$target_repo" config user.email launcher@example.invalid
printf '%s\n' '# Target' >"$target_repo/README.md"
git -C "$target_repo" add README.md
git -C "$target_repo" commit -qm 'test: target'
git -C "$target_repo" remote add origin \
  https://github.com/beroka-vn/target.git

git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git

asset=$TEST_ROOT/bootstrap.sh
sed \
  -e "s/@RELEASE_VERSION@/v9.9.9/g" \
  -e "s/@RELEASE_COMMIT@/$release_commit/g" \
  "$TEMPLATE" >"$asset"

if output=$(cd "$target_repo" &&
  sh "$asset" --client codex --client codex 2>&1)
then
  fail 'launcher accepted duplicate clients'
fi
assert_contains "$output" 'Usage:'

if output=$(cd "$TEST_ROOT" &&
  sh "$asset" --client codex --non-interactive 2>&1)
then
  fail 'launcher accepted a directory outside Git'
fi
assert_contains "$output" 'Result: REPOSITORY_REQUIRED'

git -C "$target_repo" remote set-url origin \
  https://gitlab.example.invalid/beroka-vn/target.git
if output=$(cd "$target_repo" &&
  sh "$asset" --client codex --non-interactive 2>&1)
then
  fail 'launcher accepted a non-GitHub canonical origin'
fi
assert_contains "$output" 'Result: REMOTE_MISMATCH'
git -C "$target_repo" remote set-url origin \
  https://github.com/beroka-vn/target.git

bad_asset=$TEST_ROOT/bootstrap-bad.sh
sed \
  -e 's/@RELEASE_VERSION@/v9.9.9/g' \
  -e 's/@RELEASE_COMMIT@/0000000000000000000000000000000000000000/g' \
  "$TEMPLATE" >"$bad_asset"
before=$(git -C "$target_repo" status --porcelain=v1)
if output=$(cd "$target_repo" &&
  sh "$bad_asset" --client codex --non-interactive 2>&1)
then
  fail 'launcher accepted a mismatched release commit'
fi
after=$(git -C "$target_repo" status --porcelain=v1)
[ "$before" = "$after" ] ||
  fail 'launcher changed the target before release verification'
assert_contains "$output" 'Result: RELEASE_VERIFICATION_FAILED'

: >"$calls"
output=$(cd "$target_repo" &&
  sh "$asset" --client codex --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
grep -F -- "--client codex --version v9.9.9 --non-interactive" \
  "$calls" >/dev/null ||
  fail 'launcher omitted explicit non-interactive decisions'

: >"$calls"
output=$(cd "$target_repo" &&
  script -qec \
    "sh -c 'sh -s -- --client codex <\"$asset\"'" \
    /dev/null 2>&1)
assert_contains "$output" 'LAUNCHER_INTERACTIVE=PASS'
grep -F -- "--client codex --version v9.9.9" "$calls" >/dev/null ||
  fail 'interactive launcher omitted the verified release decision'

printf '%s\n' 'One-command launcher tests: PASS'
