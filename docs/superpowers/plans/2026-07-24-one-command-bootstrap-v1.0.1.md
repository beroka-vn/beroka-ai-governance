# One-Command Bootstrap V1.0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a one-command stable-release launcher with reliable connector health, resumable OAuth setup, and additive per-environment client onboarding.

**Architecture:** Keep the existing POSIX shell CLI and pinned repository contract. Add one release-asset template that verifies its embedded tag and commit before invoking the release CLI, replace Codex's fixed three-second probe with a FIFO-backed response-driven deadline, and make partial connector outcomes explicit without rolling back successful repository registration.

**Tech Stack:** POSIX `sh`, Git, `jq`, existing Codex/Claude/Cursor CLIs, shell integration tests, GitHub Releases.

## Global Constraints

- The published `v1.0.0` tag and GitHub Release are immutable.
- Every invocation selects exactly one of `codex`, `claude`, or `cursor`.
- The official launcher targets the current Git root and never searches for another repository.
- OAuth credentials remain owned by the selected client and its OS keyring or credential store.
- Never accept, print independently, log, or store developer API tokens or OAuth credentials.
- Interactive launcher prompts use `/dev/tty`; non-interactive mode never opens a terminal or browser.
- Existing repository locks are never silently upgraded.
- Connector health has a 15-second total deadline and never infers authentication from unknown health.
- Tests use temporary HOME, XDG, client-home, and Git directories with no real credentials.
- Do not add a package manager, third-party runtime dependency, or second governance ruleset.

---

### Task 1: Replace the Fixed Codex Probe with a Response-Driven Deadline

**Files:**
- Modify: `tests/connectors.sh`
- Modify: `bin/beroka-governance:1505-1530`

**Interfaces:**
- Consumes: existing `codex_atlassian_record`, `codex_reauthentication_required`, and `codex_http_auth_required` parsers.
- Produces: `codex_connector_probe`, which sets `CONNECTOR_PROBE_OUTPUT` and returns `0` only after a terminal Codex health response or explicit authentication evidence arrives.
- Produces: `codex_probe_complete FILE`, a private predicate used only by `codex_connector_probe`.

- [ ] **Step 1: Make the fake Codex app-server capable of delayed streaming**

In `tests/connectors.sh`, replace the fake `sleep` with a deterministic poll
counter:

```sh
cat >"$FAKE_BIN/sleep" <<'EOF'
#!/bin/sh
set -eu
if [ -n "${FAKE_CODEX_READY_AFTER:-}" ]; then
  count=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-polls" 2>/dev/null || :)
  count=${count:-0}
  count=$((count + 1))
  printf '%s\n' "$count" >"$XDG_CONFIG_HOME/fake-codex-polls"
  if [ "$FAKE_CODEX_READY_AFTER" != never ] &&
     [ "$count" -ge "$FAKE_CODEX_READY_AFTER" ]
  then
    : >"$XDG_CONFIG_HOME/fake-codex-ready"
  fi
  /bin/sleep 0.01
fi
exit 0
EOF
chmod 755 "$FAKE_BIN/sleep"
```

Change the fake Codex `app-server --stdio` branch to read the three JSON-RPC
messages without waiting for EOF:

```sh
  'app-server --stdio')
    IFS= read -r request_1 || exit 1
    IFS= read -r request_2 || exit 1
    IFS= read -r request_3 || exit 1
    input=$(printf '%s\n%s\n%s\n' "$request_1" "$request_2" "$request_3")
    case "$input" in
      *'config/value/write'*)
        : >"$XDG_CONFIG_HOME/fake-codex-configured"
        printf '{"id":1,"result":{}}\n'
        ;;
      *'mcpServerStatus/list'*)
        loops=0
        while [ -n "${FAKE_CODEX_READY_AFTER:-}" ] &&
              [ ! -f "$XDG_CONFIG_HOME/fake-codex-ready" ] &&
              [ "$loops" -lt 100 ]
        do
          /bin/sleep 0.01
          loops=$((loops + 1))
        done
        [ -z "${FAKE_CODEX_READY_AFTER:-}" ] ||
          [ -f "$XDG_CONFIG_HOME/fake-codex-ready" ] ||
          exit 0
        health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-health" 2>/dev/null || :)
        case "$health" in
          healthy)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          healthy-custom-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"searchJiraIssuesUsingJql":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          auth-required|'')
            printf '%s\n' \
              '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","status":"failed","failureReason":"reauthenticationRequired"}}' \
              '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          missing)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{},"resources":[],"resourceTemplates":[],"authStatus":"notLoggedIn"}]}}'
            ;;
          failed)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
        esac
        ;;
      *) exit 1 ;;
    esac
    ;;
```

- [ ] **Step 2: Add failing delayed-response and deadline tests**

Immediately after the existing non-interactive Codex authentication test, add:

```sh
printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
for ready_after in 1 3 4; do
  rm -f \
    "$XDG_CONFIG_HOME/fake-codex-polls" \
    "$XDG_CONFIG_HOME/fake-codex-ready"
  export FAKE_CODEX_READY_AFTER=$ready_after
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fail "Codex delayed probe $ready_after unexpectedly passed authentication"
  fi
  assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
done

rm -f \
  "$XDG_CONFIG_HOME/fake-codex-polls" \
  "$XDG_CONFIG_HOME/fake-codex-ready"
export FAKE_CODEX_READY_AFTER=never
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fail 'Codex probe without a response passed'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
unset FAKE_CODEX_READY_AFTER
```

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```sh
sh tests/connectors.sh
```

Expected: FAIL for delayed response `3` or `4`.

- [ ] **Step 4: Implement the bounded response-driven Codex probe**

Add these functions immediately before `connector_probe`:

```sh
codex_probe_complete() {
  cpc_file=$1
  [ -s "$cpc_file" ] || return 1
  if codex_reauthentication_required <"$cpc_file" ||
     codex_http_auth_required <"$cpc_file"
  then
    return 0
  fi
  awk '
    index($0, "\"id\":1") &&
    (index($0, "\"result\"") || index($0, "\"error\"")) {
      complete=1
    }
    END { exit !complete }
  ' "$cpc_file"
}

codex_connector_probe() {
  ccp_dir=$(mktemp -d \
    "${TMPDIR:-/tmp}/beroka-codex-probe.XXXXXX") || return 1
  ccp_input=$ccp_dir/input
  ccp_output=$ccp_dir/output
  mkfifo "$ccp_input" || {
    rm -rf "$ccp_dir"
    return 1
  }

  codex app-server --stdio <"$ccp_input" >"$ccp_output" 2>&1 &
  ccp_pid=$!
  exec 3>"$ccp_input" || {
    kill "$ccp_pid" 2>/dev/null || :
    wait "$ccp_pid" 2>/dev/null || :
    rm -rf "$ccp_dir"
    return 1
  }
  if ! printf '%s\n' \
    '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"beroka-governance","title":"Beroka Governance","version":"1"}}}' \
    '{"method":"initialized","params":{}}' \
    '{"method":"mcpServerStatus/list","id":1,"params":{"detail":"toolsAndAuthOnly","limit":100}}' \
    >&3
  then
    exec 3>&-
    kill "$ccp_pid" 2>/dev/null || :
    wait "$ccp_pid" 2>/dev/null || :
    rm -rf "$ccp_dir"
    return 1
  fi

  ccp_elapsed=0
  ccp_complete=0
  while [ "$ccp_elapsed" -lt 15 ]; do
    if codex_probe_complete "$ccp_output"; then
      ccp_complete=1
      break
    fi
    sleep 1
    ccp_elapsed=$((ccp_elapsed + 1))
  done

  exec 3>&-
  kill "$ccp_pid" 2>/dev/null || :
  wait "$ccp_pid" 2>/dev/null || :
  CONNECTOR_PROBE_OUTPUT=$(cat "$ccp_output" 2>/dev/null || :)
  rm -rf "$ccp_dir"
  [ "$ccp_complete" -eq 1 ]
}
```

Change the start of `connector_probe` so incomplete probes are not cached:

```sh
connector_probe() {
  cp_client=$1
  [ "${CONNECTOR_PROBE_CLIENT:-}" = "$cp_client" ] && return 0
  CONNECTOR_PROBE_CLIENT=
  CONNECTOR_PROBE_OUTPUT=
  CONNECTOR_PROBE_STATUS=
  CONNECTOR_PROBE_STATE=
  CONNECTOR_PROBE_TOOLS=
  CONNECTOR_PROBE_TOOLS_OK=0
  case "$cp_client" in
    codex)
      codex_connector_probe || return 1
      ;;
```

Set the cache only after the selected client's probe completes:

```sh
  esac
  CONNECTOR_PROBE_CLIENT=$cp_client
}
```

- [ ] **Step 5: Run connector tests and verify GREEN**

Run:

```sh
sh -n bin/beroka-governance
sh -n tests/connectors.sh
sh tests/connectors.sh
```

Expected: `Connector selection tests: PASS`.

- [ ] **Step 6: Commit the probe fix**

```sh
git add bin/beroka-governance tests/connectors.sh
git commit -m "fix: wait for Codex connector health response"
```

---

### Task 2: Make Bootstrap Partial Success Explicit and Resumable

**Files:**
- Modify: `tests/connectors.sh`
- Modify: `tests/bootstrap.sh`
- Modify: `tests/routing.sh`
- Modify: `bin/beroka-governance:775-880`
- Modify: `bin/beroka-governance:2235-2250`
- Modify: `bin/beroka-governance:2460-2590`

**Interfaces:**
- Consumes: Task 1's `connector_health` return contract: `0` healthy, `1` authentication required, `2` unclassifiable health.
- Produces: `auth_pending CLIENT`, which exits with `AUTH_PENDING`.
- Produces: `connector_health_unavailable CLIENT`, which exits with `CONNECTOR_HEALTH_UNAVAILABLE`.
- Produces: phase summary fields printed by `cmd_bootstrap`.

- [ ] **Step 1: Add failing result-contract tests**

Near the existing declined Codex authentication test in `tests/connectors.sh`,
add:

```sh
printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$(printf 'n\n' |
  script -qec "$CLI setup-connectors --client codex" /dev/null 2>&1)
then
  fail 'interactive setup accepted pending authentication'
fi
assert_contains "$output" 'Connector: AUTH_PENDING'
assert_contains "$output" 'Result: AUTH_PENDING'
assert_contains "$output" \
  'Resume: beroka-governance setup-connectors --client codex'

export FAKE_CODEX_READY_AFTER=never
rm -f \
  "$XDG_CONFIG_HOME/fake-codex-polls" \
  "$XDG_CONFIG_HOME/fake-codex-ready"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fail 'setup accepted unavailable connector health'
fi
assert_contains "$output" 'Connector: HEALTH_UNAVAILABLE'
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
unset FAKE_CODEX_READY_AFTER
```

Update the existing Claude `unrelated-only` and Cursor
`ready-tools-failed` assertions from:

```sh
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
```

to:

```sh
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
```

In `tests/routing.sh`, change only the connector-health-unknown expectations
for malformed Codex inventory and disconnected Claude status to:

```sh
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
```

Keep unrelated `GOVERNANCE_NOT_READY` assertions unchanged.

In `tests/bootstrap.sh`, add assertions after the first successful bootstrap:

```sh
assert_contains "$output" 'Release: PASS'
assert_contains "$output" 'Repository registration: PASS'
assert_contains "$output" 'Client entrypoint: ADDED'
```

After the repeated Codex bootstrap, add:

```sh
assert_contains "$output" 'Repository registration: NO_CHANGE'
assert_contains "$output" 'Client entrypoint: ALREADY_CONFIGURED'
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```sh
sh tests/connectors.sh
sh tests/bootstrap.sh
sh tests/routing.sh
```

Expected: FAIL because interactive decline still returns
`ATLASSIAN_AUTH_REQUIRED` and bootstrap does not print phase summaries.

- [ ] **Step 3: Add explicit partial-result helpers**

Immediately after `auth_required`, add:

```sh
auth_pending() {
  ap_client=$1
  printf '%s\n' \
    "Client: $ap_client" \
    'Provider: atlassian' \
    'Authentication: AUTH_REQUIRED' \
    'Connector: AUTH_PENDING' \
    "Remediation: $(oauth_command "$ap_client")" \
    "Resume: beroka-governance setup-connectors --client $ap_client"
  [ "$ap_client" != claude ] ||
    printf '%s\n' 'In Claude: /mcp -> atlassian -> Authenticate'
  die AUTH_PENDING
}

connector_health_unavailable() {
  chu_client=$1
  printf '%s\n' \
    "Client: $chu_client" \
    'Provider: atlassian' \
    'Connector: HEALTH_UNAVAILABLE' \
    "Resume: beroka-governance setup-connectors --client $chu_client"
  die CONNECTOR_HEALTH_UNAVAILABLE
}
```

- [ ] **Step 4: Route interactive, unknown-health, Doctor, and preflight outcomes**

In `cmd_setup_connectors`:

```sh
  case "$setup_health" in
    0)
      printf '%s\n' \
        "Client: $setup_client" \
        'Connector: PASS' \
        'Authentication: PASS' \
        'Result: PASS'
      return
      ;;
    1) ;;
    *) connector_health_unavailable "$setup_client" ;;
  esac
```

For an accepted OAuth prompt:

```sh
        run_oauth "$setup_client" || auth_pending "$setup_client"
        setup_health=0
        connector_health "$setup_client" || setup_health=$?
        case "$setup_health" in
          0) ;;
          1) auth_pending "$setup_client" ;;
          *) connector_health_unavailable "$setup_client" ;;
        esac
```

For an interactive decline, call:

```sh
  [ "$setup_interactive" -eq 0 ] ||
    auth_pending "$setup_client"
  auth_required "$setup_client"
```

Replace unclassifiable connector-health branches in connector-dependent
preflight and `cmd_doctor` with:

```sh
connector_health_unavailable "$pf_client"
```

Use `$pf_client` in preflight and the following exact call in Doctor:

```sh
connector_health_unavailable "$doctor_client"
```

- [ ] **Step 5: Print bootstrap phase state before connector setup**

After `bs_after=$(managed_repo_snapshot "$bs_repo")`, add:

```sh
  if [ "$bs_before" = "$bs_after" ]; then
    bs_registration=NO_CHANGE
    bs_entrypoint=ALREADY_CONFIGURED
    bs_changes=NONE
  else
    bs_registration=PASS
    bs_entrypoint=ADDED
    bs_changes=REVIEW_REQUIRED
  fi
  printf '%s\n' \
    'Release: PASS' \
    "Repository registration: $bs_registration" \
    "Client entrypoint: $bs_entrypoint"
```

Remove the later duplicate assignment of `bs_changes`; retain the final
successful summary:

```sh
  printf '%s\n' \
    "Version: $bs_version" \
    "Selected client: $bs_client" \
    "Repository changes: $bs_changes" \
    'Next: review and commit repository changes, then start a fresh AI session' \
    'Result: PASS'
```

- [ ] **Step 6: Run bootstrap and connector tests**

Run:

```sh
sh -n bin/beroka-governance
sh tests/connectors.sh
sh tests/bootstrap.sh
sh tests/routing.sh
```

Expected:

```text
Connector selection tests: PASS
Bootstrap onboarding tests: PASS
```

- [ ] **Step 7: Commit resumable result behavior**

```sh
git add bin/beroka-governance tests/connectors.sh tests/bootstrap.sh
git add tests/routing.sh
git commit -m "feat: make connector setup resumable"
```

---

### Task 3: Add the Verified GitHub Release Launcher

**Files:**
- Create: `release/bootstrap.sh.in`
- Create: `tests/launcher.sh`

**Interfaces:**
- Consumes: `@RELEASE_VERSION@` and `@RELEASE_COMMIT@` substituted when the release asset is built.
- Produces: the published `bootstrap.sh` asset.
- Invokes: `beroka-governance bootstrap GIT_ROOT --client CLIENT --version RELEASE` in interactive mode.
- Invokes: the same command with `--non-interactive` in non-interactive mode.

- [ ] **Step 1: Write the isolated launcher test**

Create `tests/launcher.sh`:

```sh
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
```

- [ ] **Step 2: Run the launcher test and verify RED**

Run:

```sh
sh tests/launcher.sh
```

Expected: FAIL because `release/bootstrap.sh.in` does not exist.

- [ ] **Step 3: Implement the release launcher template**

Create `release/bootstrap.sh.in`:

```sh
#!/bin/sh
set -eu

PROGRAM=beroka-governance-bootstrap
REMOTE_URL=https://github.com/beroka-vn/beroka-ai-governance.git
RELEASE_VERSION='@RELEASE_VERSION@'
RELEASE_COMMIT='@RELEASE_COMMIT@'

die() {
  code=$1
  shift
  printf '%s\n' "Result: $code" >&2
  [ "$#" -eq 0 ] || printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    "Usage: $PROGRAM --client codex|claude|cursor [--non-interactive]"
}

client=
non_interactive=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --client)
      [ -z "$client" ] && [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      case "$2" in
        codex|claude|cursor) client=$2 ;;
        *) usage >&2; exit 2 ;;
      esac
      shift 2
      ;;
    --non-interactive)
      [ "$non_interactive" -eq 0 ] || {
        usage >&2
        exit 2
      }
      non_interactive=1
      shift
      ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "$client" ] || {
  usage >&2
  exit 2
}

printf '%s\n' "$RELEASE_VERSION" |
  grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' ||
  die RELEASE_VERIFICATION_FAILED 'Invalid embedded release version'
printf '%s\n' "$RELEASE_COMMIT" |
  grep -Eq '^[0-9a-f]{40}$' ||
  die RELEASE_VERIFICATION_FAILED 'Invalid embedded release commit'

repo=$(git rev-parse --show-toplevel 2>/dev/null) ||
  die REPOSITORY_REQUIRED 'Run this command inside the repository to register'
repo=$(CDPATH= cd -- "$repo" && pwd -P) ||
  die REPOSITORY_REQUIRED 'Cannot resolve the current Git root'

origin_url=$(git -C "$repo" config --get remote.origin.url 2>/dev/null) ||
  die REMOTE_MISMATCH 'Cannot resolve the canonical GitHub origin'
case "$origin_url" in
  https://github.com/*) origin_slug=${origin_url#https://github.com/} ;;
  git@github.com:*) origin_slug=${origin_url#git@github.com:} ;;
  ssh://git@github.com/*)
    origin_slug=${origin_url#ssh://git@github.com/}
    ;;
  *) die REMOTE_MISMATCH 'Canonical origin is not a GitHub repository' ;;
esac
while [ "${origin_slug%/}" != "$origin_slug" ]; do
  origin_slug=${origin_slug%/}
done
origin_slug=${origin_slug%.git}
printf '%s\n' "$origin_slug" |
  grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ||
  die REMOTE_MISMATCH 'Canonical origin is not a GitHub repository'

bootstrap_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-governance-bootstrap.XXXXXX") ||
  die GOVERNANCE_NOT_READY 'Cannot create the bootstrap directory'
trap 'rm -rf "$bootstrap_root"' EXIT HUP INT TERM

git clone --quiet --depth 1 --single-branch \
  --branch "$RELEASE_VERSION" \
  "$REMOTE_URL" "$bootstrap_root/repo" ||
  die RELEASE_VERIFICATION_FAILED 'Cannot clone the embedded release tag'

tag_type=$(git -C "$bootstrap_root/repo" \
  cat-file -t "refs/tags/$RELEASE_VERSION" 2>/dev/null || :)
actual_commit=$(git -C "$bootstrap_root/repo" \
  rev-parse "$RELEASE_VERSION^{commit}" 2>/dev/null || :)
[ "$tag_type" = tag ] && [ "$actual_commit" = "$RELEASE_COMMIT" ] ||
  die RELEASE_VERIFICATION_FAILED \
    'The release tag does not match the embedded commit'

cli=$bootstrap_root/repo/bin/beroka-governance
if [ "$non_interactive" -eq 1 ]; then
  sh "$cli" bootstrap "$repo" \
    --client "$client" \
    --version "$RELEASE_VERSION" \
    --non-interactive
else
  [ -t 1 ] && ( : </dev/tty ) 2>/dev/null ||
    die TTY_REQUIRED \
      "Retry with: $PROGRAM --client $client --non-interactive"
  sh "$cli" bootstrap "$repo" \
    --client "$client" \
    --version "$RELEASE_VERSION" \
    </dev/tty
fi
```

- [ ] **Step 4: Run launcher syntax and behavior tests**

Run:

```sh
sh -n release/bootstrap.sh.in
sh -n tests/launcher.sh
sh tests/launcher.sh
```

Expected: `One-command launcher tests: PASS`.

- [ ] **Step 5: Commit the launcher**

```sh
git add release/bootstrap.sh.in tests/launcher.sh
git commit -m "feat: add verified release bootstrap launcher"
```

---

### Task 4: Document V1.0.1 and Enforce Release Readiness

**Files:**
- Modify: `VERSION`
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `tests/release.sh`
- Modify: `tests/connectors.sh`
- Modify: `tests/bootstrap.sh`

**Interfaces:**
- Consumes: Task 2 result names and Task 3 launcher URL.
- Produces: copy-paste onboarding documentation and release-readiness assertions for `v1.0.1`.

- [ ] **Step 1: Add failing documentation and version assertions**

Update the release version assertion in `tests/release.sh`:

```sh
[ "$(cat "$ROOT/VERSION")" = v1.0.1 ] ||
  fail 'VERSION is not v1.0.1'
```

Add:

```sh
require_text README.md \
  'releases/latest/download/bootstrap.sh'
require_text README.md \
  'sh -s -- --client codex'
require_text README.md \
  'one client on each execution environment'
require_text handbook.md 'AUTH_PENDING'
require_text handbook.md 'CONNECTOR_HEALTH_UNAVAILABLE'
require_text PACKAGE-DESIGN.md '15-second total deadline'
[ -f "$ROOT/release/bootstrap.sh.in" ] ||
  fail 'missing release launcher template'
```

In the documentation checks at the end of `tests/connectors.sh` and
`tests/bootstrap.sh`, require the same result names and launcher URL.

- [ ] **Step 2: Run release and documentation tests and verify RED**

Run:

```sh
sh tests/release.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
```

Expected: FAIL because `VERSION` and the user-facing documents still describe
the first `v1.0.0` onboarding flow.

- [ ] **Step 3: Update the package version**

Change `VERSION` to:

```text
v1.0.1
```

- [ ] **Step 4: Replace README Quick start with the one-command flow**

The first command shown under `## Quick start` must be:

```sh
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex
```

Document:

```text
Replace codex with claude or cursor. Run the command from the Git root to
register. The client flag is mandatory. Repeat setup once for each client on
each execution environment; all enabled clients load the same pinned
governance release. Changing a model inside the same client needs no setup.
```

Keep the explicit automation example:

```sh
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive
```

- [ ] **Step 5: Document partial success and remote execution**

In `handbook.md`, add the exact operator guidance:

```text
AUTH_PENDING means installation and repository registration succeeded but the
selected client's OAuth is incomplete. Run the printed Resume command; do not
delete or recreate the lock.

CONNECTOR_HEALTH_UNAVAILABLE means governance could not classify connector
health before the 15-second deadline. External connector-dependent writes
remain blocked. Run the printed Resume command after connectivity recovers.

A client started from a VS Code Remote SSH terminal runs on the remote host.
Repository entrypoints are shared through Git, while the CLI, connector, and
OAuth setup are local to that remote execution environment.
```

In `PACKAGE-DESIGN.md`, define the response-driven 15-second deadline, the
launcher tag/commit verification boundary, and the repository/client/environment
scope from the approved spec.

- [ ] **Step 6: Run all focused documentation tests**

Run:

```sh
sh tests/release.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
```

Expected:

```text
First public release readiness: PASS
Connector selection tests: PASS
Bootstrap onboarding tests: PASS
```

- [ ] **Step 7: Commit V1.0.1 documentation**

```sh
git add \
  VERSION README.md handbook.md PACKAGE-DESIGN.md \
  tests/release.sh tests/connectors.sh tests/bootstrap.sh
git commit -m "docs: publish one-command v1.0.1 onboarding"
```

---

### Task 5: Verify, Pilot, Merge, and Publish V1.0.1

**Files:**
- Verify only before merge.
- Generate outside the repository: temporary `bootstrap.sh` release asset.
- Do not modify the published `v1.0.0` tag or Release.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: reviewed implementation branch, canonical pilots, annotated
  `v1.0.1`, and a stable GitHub Release with `bootstrap.sh`.

- [ ] **Step 1: Run the complete local verification suite**

Run:

```sh
git diff --check
sh -n bin/beroka-governance
sh -n release/bootstrap.sh.in
sh -n tests/smoke.sh
sh -n tests/connectors.sh
sh -n tests/bootstrap.sh
sh -n tests/launcher.sh
sh -n tests/routing.sh
sh -n tests/release.sh
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
sh tests/launcher.sh
sh tests/routing.sh
sh tests/release.sh
sh tests/documentation-architecture.sh
```

Expected: every command exits `0`; each suite prints its PASS marker.

- [ ] **Step 2: Verify immutable V1.0.0 and branch scope**

Run:

```sh
v1_object=$(git rev-parse refs/tags/v1.0.0)
v1_commit=$(git rev-parse 'refs/tags/v1.0.0^{commit}')
git cat-file -t refs/tags/v1.0.0
git diff --stat origin/main...HEAD
git status --short
printf 'v1.0.0 object=%s commit=%s\n' "$v1_object" "$v1_commit"
```

Expected: tag type is `tag`, only planned files differ, and the worktree is
clean.

- [ ] **Step 3: Push the feature branch and open a draft PR**

Run:

```sh
git push -u origin agent/one-command-bootstrap-v1.0.1
gh pr create \
  --repo beroka-vn/beroka-ai-governance \
  --draft \
  --base main \
  --head agent/one-command-bootstrap-v1.0.1 \
  --title "Add one-command governance bootstrap" \
  --body "Adds the verified stable-release launcher, response-driven connector health, resumable OAuth setup, and isolated onboarding tests. Does not modify v1.0.0."
```

Expected: GitHub returns the new draft PR URL.

- [ ] **Step 4: Request review and merge through the normal PR workflow**

Do not create `v1.0.1` before the PR is approved and merged. After merge:

```sh
git fetch origin main
merge_commit=$(git rev-parse origin/main)
git merge-base --is-ancestor HEAD "$merge_commit"
git show origin/main:VERSION
```

Expected: the feature head is an ancestor of `origin/main` and `VERSION` is
`v1.0.1`.

- [ ] **Step 5: Build and verify the candidate release asset**

Run:

```sh
release=v1.0.1
merge_commit=$(git rev-parse origin/main)
if test -n "$(git ls-remote --tags origin \
  refs/tags/v1.0.1 'refs/tags/v1.0.1^{}')"
then
  printf '%s\n' 'STOP: remote v1.0.1 already exists' >&2
  exit 1
fi
if git show-ref --verify --quiet refs/tags/v1.0.1; then
  printf '%s\n' 'STOP: local v1.0.1 already exists' >&2
  exit 1
fi
git tag -a "$release" "$merge_commit" \
  -m "Beroka AI governance package v1.0.1 candidate"
asset_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-v1.0.1-asset.XXXXXX")
asset=$asset_root/bootstrap.sh
sed \
  -e "s/@RELEASE_VERSION@/$release/g" \
  -e "s/@RELEASE_COMMIT@/$merge_commit/g" \
  release/bootstrap.sh.in >"$asset"
chmod 755 "$asset"
sh -n "$asset"
grep -F "@RELEASE_" "$asset" && exit 1 || :
```

Expected: syntax PASS and no unresolved release placeholders.

- [ ] **Step 6: Run canonical isolated candidate pilots before publication**

Run:

```sh
pilot_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-v1.0.1-pilot.XXXXXX")
git clone --depth 1 \
  https://github.com/hungnx77/Beroka_Backend.git \
  "$pilot_root/backend"
git clone --depth 1 \
  https://github.com/cuongngo1801-beroka/Beroka_Frontend.git \
  "$pilot_root/frontend"
git clone --depth 1 \
  https://github.com/beroka-vn/beroka-ai-governance.git \
  "$pilot_root/governance"

export HOME=$pilot_root/home
export XDG_DATA_HOME=$pilot_root/data
export XDG_CONFIG_HOME=$pilot_root/config
export BEROKA_GOV_BIN_DIR=$pilot_root/bin
export CODEX_HOME=$pilot_root/codex
export PATH=$BEROKA_GOV_BIN_DIR:$PATH
mkdir -p \
  "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" \
  "$BEROKA_GOV_BIN_DIR" "$CODEX_HOME"

canonical_url=https://github.com/beroka-vn/beroka-ai-governance.git
common_git=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
rewrite_url=${common_git%/.git}
git config --global \
  url."file://$rewrite_url".insteadOf \
  "$canonical_url"

pilot_one() {
  po_repo=$1
  set +e
  po_output=$(cd "$po_repo" &&
    sh "$asset" --client codex --non-interactive 2>&1)
  po_status=$?
  set -e
  if [ "$po_status" -eq 0 ]; then
    printf '%s\n' "$po_output" | grep -F 'Result: PASS' >/dev/null
  else
    printf '%s\n' "$po_output" |
      grep -F 'Result: ATLASSIAN_AUTH_REQUIRED' >/dev/null
    printf '%s\n' "$po_output" |
      grep -F 'Remediation: codex mcp login atlassian' >/dev/null
  fi
  grep -Fx 'VERSION=v1.0.1' \
    "$po_repo/.beroka-governance.lock" >/dev/null
  grep -Fx "COMMIT=$merge_commit" \
    "$po_repo/.beroka-governance.lock" >/dev/null
  grep -Fx 'CLIENTS=codex' \
    "$po_repo/.beroka-governance.lock" >/dev/null
  test -f "$po_repo/AGENTS.md"
  test ! -e "$po_repo/CLAUDE.md"
  test ! -e "$po_repo/.cursor"
  beroka-governance doctor "$po_repo"
}

pilot_one "$pilot_root/backend"
pilot_one "$pilot_root/frontend"
pilot_one "$pilot_root/governance"

git config --global --unset-all \
  url."file://$rewrite_url".insteadOf
```

Expected: each lock contains the verified merge commit, each base Doctor
returns PASS, and isolated missing OAuth returns only the exact fail-closed
Codex remediation.

- [ ] **Step 7: Create and push the new annotated tag without force**

First verify the remote tag and release are absent:

```sh
git ls-remote --tags origin \
  refs/tags/v1.0.1 'refs/tags/v1.0.1^{}'
gh release view v1.0.1 \
  --repo beroka-vn/beroka-ai-governance
```

The first command must print nothing and the second must report no release.
Then:

```sh
git push origin refs/tags/v1.0.1:refs/tags/v1.0.1
```

Never use `--force`.

- [ ] **Step 8: Publish and verify the GitHub Release asset**

Run:

```sh
gh release create v1.0.1 \
  --repo beroka-vn/beroka-ai-governance \
  --verify-tag \
  --latest \
  --title "Beroka AI Governance v1.0.1" \
  --notes "One-command onboarding, response-driven connector health, and resumable multi-client setup." \
  "$asset#bootstrap.sh"

curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  grep -F "RELEASE_COMMIT='$merge_commit'"

gh release view v1.0.1 \
  --repo beroka-vn/beroka-ai-governance \
  --json url,tagName,name,isDraft,isPrerelease,publishedAt
```

Expected: the latest asset contains the verified merge commit and the release
is published, stable, and non-draft.

- [ ] **Step 9: Run one post-publication clean-machine simulation**

In a new temporary HOME/XDG/CODEX_HOME and a fresh canonical HTTPS repository
clone, run the public command:

```sh
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive
```

Expected: no `GOVERNANCE_NOT_READY` timing failure. The result is either PASS
with existing isolated authentication or the exact fail-closed
`ATLASSIAN_AUTH_REQUIRED` remediation. Base Doctor must PASS, and the only
repository additions are `.beroka-governance.lock` and `AGENTS.md`.
