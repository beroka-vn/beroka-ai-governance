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

# script(1) has incompatible flags between util-linux (Linux) and BSD
# (macOS), and macOS's script mishandles piped (non-tty) stdin. Use
# Python's pty module instead: it is portable across both runners and
# correctly relays piped stdin into the child. The child's real exit
# status is captured via a status file written from inside the pty,
# since pty.spawn's own return value is not a reliable exit code across
# Python versions.
run_pty() {
  rp_command=$1
  rp_status_file=$(mktemp)
  /usr/bin/python3 -c '
import pty, sys, shlex
command, status_file = sys.argv[1], sys.argv[2]
wrapped = command + "; echo $? > " + shlex.quote(status_file)
pty.spawn(["/bin/sh", "-c", wrapped])
' "$rp_command" "$rp_status_file"
  rp_status=$(cat "$rp_status_file" 2>/dev/null || echo 1)
  rm -f "$rp_status_file"
  return "$rp_status"
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected [$2] in [$1]" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "did not expect [$2] in [$1]" ;;
    *) ;;
  esac
}

snapshot_repo() {
  sr_repo=$1
  {
    git -C "$sr_repo" status --porcelain=v1 --untracked-files=all
    git -C "$sr_repo" ls-files -s
    git -C "$sr_repo" diff --binary
    git -C "$sr_repo" diff --cached --binary
    git -C "$sr_repo" rev-parse --verify HEAD
    git -C "$sr_repo" symbolic-ref -q HEAD || printf '%s\n' DETACHED
    git -C "$sr_repo" show-ref --head
    git -C "$sr_repo" config --local --list
  }
}

source_repo=$TEST_ROOT/source
target_repo=$TEST_ROOT/target
calls=$TEST_ROOT/calls
mkdir -p "$source_repo/bin" "$target_repo"

cat >"$source_repo/bin/beroka-governance" <<EOF
#!/bin/sh
set -eu
[ "\$1" = bootstrap ] || exit 64
shift
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

before=$(snapshot_repo "$target_repo")
git -C "$target_repo" remote add snapshot-probe \
  https://github.com/beroka-vn/snapshot-probe.git
[ "$before" != "$(snapshot_repo "$target_repo")" ] ||
  fail 'repository snapshot omitted remote configuration'
git -C "$target_repo" remote remove snapshot-probe

git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git

asset=$TEST_ROOT/bootstrap.sh
sed \
  -e "s/@RELEASE_VERSION@/v9.9.9/g" \
  -e "s/@RELEASE_COMMIT@/$release_commit/g" \
  "$TEMPLATE" >"$asset"

if output=$(cd "$TEST_ROOT" && sh "$asset" 2>&1); then
  fail 'launcher accepted a missing client'
fi
assert_contains "$output" 'Usage:'
assert_not_contains "$output" 'Result: REPOSITORY_REQUIRED'

if output=$(cd "$TEST_ROOT" &&
  sh "$asset" --client invalid --non-interactive 2>&1)
then
  fail 'launcher accepted an invalid client'
fi
assert_contains "$output" 'Usage:'
assert_not_contains "$output" 'Result: REPOSITORY_REQUIRED'

if output=$(cd "$target_repo" &&
  sh "$asset" --client codex --client codex 2>&1)
then
  fail 'launcher accepted duplicate clients'
fi
assert_contains "$output" 'Usage:'

if output=$(cd "$target_repo" &&
  sh "$asset" --client codex --upgrade --upgrade 2>&1)
then
  fail 'launcher accepted duplicate upgrade selection'
fi
assert_contains "$output" 'Usage:'

: >"$calls"
output=$(cd "$TEST_ROOT" &&
  sh "$asset" --client codex --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
grep -Fx -- \
  "--client codex --version v9.9.9 --expected-commit $release_commit --non-interactive" \
  "$calls" >/dev/null ||
  fail 'launcher omitted the verified release commit'

for launcher_case in clean dirty detached ambiguous-remote; do
  case "$launcher_case" in
    dirty) printf '%s\n' dirty >"$target_repo/dirty" ;;
    detached) git -C "$target_repo" checkout -q --detach ;;
    ambiguous-remote)
      git -C "$target_repo" remote add mirror \
        https://github.com/beroka-vn/target-mirror.git
      ;;
  esac
  before=$(snapshot_repo "$target_repo")
  : >"$calls"
  output=$(cd "$target_repo" &&
    sh "$asset" --client codex --non-interactive)
  assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
  grep -Fx -- \
    "--client codex --version v9.9.9 --expected-commit $release_commit --non-interactive" \
    "$calls" >/dev/null ||
    fail "launcher omitted the verified release commit ($launcher_case)"
  [ "$before" = "$(snapshot_repo "$target_repo")" ] ||
    fail "launcher changed the application repository ($launcher_case)"
done

git -C "$target_repo" remote remove mirror

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

printf '%s\n' competing >"$source_repo/VERSION"
git -C "$source_repo" add VERSION
git -C "$source_repo" commit -qm 'test: competing release branch'
git -C "$source_repo" branch v9.9.9
fake_bin=$TEST_ROOT/fake-bin
real_git=$(command -v git)
mkdir -p "$fake_bin"
cat >"$fake_bin/git" <<EOF
#!/bin/sh
set -eu
if [ "\$#" -gt 0 ] && [ "\$1" = clone ]; then
  "$real_git" "\$@"
  destination=
  for argument do
    destination=\$argument
  done
  "$real_git" -C "\$destination" fetch --quiet --depth 1 \\
    "file://$source_repo" refs/tags/v9.9.9:refs/tags/v9.9.9
  "$real_git" -C "\$destination" fetch --quiet --depth 2 \\
    "file://$source_repo" refs/heads/v9.9.9
  "$real_git" -C "\$destination" checkout --quiet FETCH_HEAD
else
  exec "$real_git" "\$@"
fi
EOF
chmod 755 "$fake_bin/git"
before=$(git -C "$target_repo" status --porcelain=v1)
if output=$(cd "$target_repo" &&
  PATH="$fake_bin:$PATH" sh "$asset" --client codex --non-interactive 2>&1)
then
  fail 'launcher accepted a competing release branch'
fi
after=$(git -C "$target_repo" status --porcelain=v1)
[ "$before" = "$after" ] ||
  fail 'launcher changed the target before HEAD verification'
assert_contains "$output" 'Result: RELEASE_VERIFICATION_FAILED'
assert_contains "$output" 'The cloned release does not match the embedded commit'
git -C "$source_repo" branch -D v9.9.9 >/dev/null

: >"$calls"
output=$(cd "$target_repo" &&
  sh "$asset" --client codex --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
grep -Fx -- \
  "--client codex --version v9.9.9 --expected-commit $release_commit --non-interactive" \
  "$calls" >/dev/null ||
  fail 'launcher omitted verified non-interactive decisions'

: >"$calls"
output=$(cd "$target_repo" &&
  sh "$asset" --client codex --upgrade --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
grep -Fx -- \
  "--client codex --version v9.9.9 --expected-commit $release_commit --upgrade --non-interactive" \
  "$calls" >/dev/null ||
  fail 'launcher omitted verified upgrade selection'

: >"$calls"
output=$(cd "$target_repo" &&
  run_pty \
    "sh -c 'sh -s -- --client codex <\"$asset\"'" 2>&1)
assert_contains "$output" 'LAUNCHER_INTERACTIVE=PASS'
grep -Fx -- \
  "--client codex --version v9.9.9 --expected-commit $release_commit" \
  "$calls" >/dev/null ||
  fail 'interactive launcher omitted the verified release commit'

jq_root=$TEST_ROOT/jq-dependency
jq_bin=$jq_root/bin
jq_ready=$jq_root/ready
jq_calls=$jq_root/calls
mkdir -p "$jq_bin" "$jq_ready"
for executable in git grep mktemp rm sh; do
  ln -s "$(command -v "$executable")" "$jq_bin/$executable"
done
cat >"$jq_bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' 0
EOF
cat >"$jq_bin/apt-get" <<'EOF'
#!/bin/sh
set -eu
printf 'apt-get %s\n' "$*" >>"$JQ_INSTALL_CALLS"
case "$1" in
  update) ;;
  install)
    [ "$2" = -y ] && [ "$3" = jq ] || exit 64
    /bin/cp "$JQ_READY_BIN/jq" "$JQ_ACTIVE_BIN/jq"
    /bin/chmod 755 "$JQ_ACTIVE_BIN/jq"
    ;;
  *) exit 64 ;;
esac
EOF
cat >"$jq_ready/jq" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$jq_bin/id" "$jq_bin/apt-get" "$jq_ready/jq"
: >"$jq_calls"
if output=$(cd "$target_repo" &&
  PATH="$jq_bin" JQ_INSTALL_CALLS="$jq_calls" \
  /bin/sh "$asset" --client codex --non-interactive 2>&1)
then
  fail 'non-interactive launcher accepted missing jq'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
assert_contains "$output" 'Remediation: install jq'
[ ! -s "$jq_calls" ] ||
  fail 'non-interactive launcher attempted to install jq'

output=$(cd "$target_repo" &&
  printf 'y\n' |
  PATH="$jq_bin" \
  JQ_INSTALL_CALLS="$jq_calls" \
  JQ_READY_BIN="$jq_ready" \
  JQ_ACTIVE_BIN="$jq_bin" \
  run_pty \
    "/bin/sh $asset --client codex" 2>&1)
assert_contains "$output" \
  'Missing dependency: jq. Install with apt-get (may request sudo)?'
[ "$(cat "$jq_calls")" = "$(printf '%s\n%s' \
  'apt-get update' 'apt-get install -y jq')" ] ||
  fail 'interactive launcher did not install only jq'

cursor_root=$TEST_ROOT/cursor-dependency
cursor_bin=$cursor_root/bin
cursor_calls=$cursor_root/calls
cursor_success=$cursor_root/install-success.sh
cursor_failure=$cursor_root/install-failure.sh
cursor_invalid=$cursor_root/install-invalid.sh
mkdir -p "$cursor_bin"
for executable in bash cat git grep id jq mktemp rm sh; do
  ln -s "$(command -v "$executable")" "$cursor_bin/$executable"
done
cat >"$cursor_success" <<'EOF'
#!/bin/sh
set -eu
/bin/mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/cursor-agent" <<'AGENT'
#!/bin/sh
case "$*" in
  --version) printf '%s\n' 2026.07.23-test ;;
  'mcp login --help') exit 0 ;;
  *) exit 1 ;;
esac
AGENT
/bin/chmod 755 "$HOME/.local/bin/cursor-agent"
EOF
cat >"$cursor_failure" <<'EOF'
#!/bin/sh
exit 9
EOF
cat >"$cursor_invalid" <<'EOF'
#!/bin/sh
set -eu
/bin/mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/cursor-agent" <<'AGENT'
#!/bin/sh
case "$*" in
  --version) printf '%s\n' broken-test ;;
  *) exit 1 ;;
esac
AGENT
/bin/chmod 755 "$HOME/.local/bin/cursor-agent"
EOF
cat >"$cursor_bin/curl" <<'EOF'
#!/bin/sh
set -eu
printf 'curl %s\n' "$*" >>"$CURSOR_INSTALL_CALLS"
[ "$1" = -fsS ] &&
  [ "$2" = https://cursor.com/install ] &&
  [ "$3" = -o ] &&
  [ "$#" -eq 4 ] ||
  exit 64
case "${CURSOR_INSTALL_MODE:-success}" in
  success) /bin/cp "$CURSOR_SUCCESS_INSTALLER" "$4" ;;
  failure) /bin/cp "$CURSOR_FAILURE_INSTALLER" "$4" ;;
  invalid) /bin/cp "$CURSOR_INVALID_INSTALLER" "$4" ;;
  *) exit 64 ;;
esac
EOF
chmod 755 "$cursor_bin/curl"

: >"$cursor_calls"
output=$(
  printf 'y\n' |
  PATH="$cursor_bin" \
  CURSOR_INSTALL_CALLS="$cursor_calls" \
  CURSOR_SUCCESS_INSTALLER="$cursor_success" \
  CURSOR_FAILURE_INSTALLER="$cursor_failure" \
  CURSOR_INVALID_INSTALLER="$cursor_invalid" \
  run_pty \
    "/bin/sh $asset --client cursor" 2>&1
)
assert_contains "$output" \
  'Install Cursor Agent CLI from https://cursor.com/install? [y/N]'
assert_contains "$output" 'LAUNCHER_INTERACTIVE=PASS'
grep -F 'curl -fsS https://cursor.com/install -o ' "$cursor_calls" \
  >/dev/null ||
  fail 'launcher did not stage the official Cursor installer'
[ -x "$HOME/.local/bin/cursor-agent" ] ||
  fail 'launcher did not install cursor-agent into the user bin directory'

: >"$cursor_calls"
output=$(PATH="$HOME/.local/bin:$cursor_bin" \
  CURSOR_INSTALL_CALLS="$cursor_calls" \
  /bin/sh "$asset" --client cursor --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
[ ! -s "$cursor_calls" ] ||
  fail 'launcher reinstalled a healthy cursor-agent'

rm -f "$HOME/.local/bin/cursor-agent"
: >"$cursor_calls"
if output=$(PATH="$cursor_bin" CURSOR_INSTALL_CALLS="$cursor_calls" \
  /bin/sh "$asset" --client cursor --non-interactive 2>&1)
then
  fail 'non-interactive launcher installed cursor-agent'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
[ ! -s "$cursor_calls" ] ||
  fail 'non-interactive launcher called the Cursor installer'

: >"$cursor_calls"
if output=$(
  printf 'n\n' |
  PATH="$cursor_bin" CURSOR_INSTALL_CALLS="$cursor_calls" \
  run_pty \
    "/bin/sh $asset --client cursor" 2>&1
)
then
  fail 'launcher accepted declined Cursor installation'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
[ ! -s "$cursor_calls" ] ||
  fail 'declined Cursor installation called curl'

for cursor_mode in failure invalid; do
  rm -f "$HOME/.local/bin/cursor-agent"
  : >"$cursor_calls"
  if output=$(
    printf 'y\n' |
    PATH="$cursor_bin" \
    CURSOR_INSTALL_CALLS="$cursor_calls" \
    CURSOR_INSTALL_MODE="$cursor_mode" \
    CURSOR_SUCCESS_INSTALLER="$cursor_success" \
    CURSOR_FAILURE_INSTALLER="$cursor_failure" \
    CURSOR_INVALID_INSTALLER="$cursor_invalid" \
    run_pty \
      "/bin/sh $asset --client cursor" 2>&1
  )
  then
    fail "launcher accepted $cursor_mode Cursor installation"
  fi
  assert_contains "$output" 'Result: DEPENDENCY_MISSING'
done

printf '%s\n' 'One-command launcher tests: PASS'
