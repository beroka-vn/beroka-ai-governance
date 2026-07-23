# Client-Selected Connector Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit, client-selected Atlassian MCP setup and read-only health reporting for Codex, Claude Code, and Cursor.

**Architecture:** Extend the existing POSIX shell CLI with one shared setup/health flow and three small client branches. Keep governance-only commands unchanged, delegate OAuth to each client, and normalize client status into stable Beroka result codes. Use one isolated shell test with fake client executables and temporary HOME/XDG roots.

**Tech Stack:** POSIX shell, Git, Codex/Claude/Cursor native MCP commands, `jq` only for Cursor JSON preservation.

## Global Constraints

- `--client codex|claude|cursor` selects exactly one client per invocation.
- Interactive auto-detection may select only one confirmed client and never configures all detected clients.
- Non-interactive mode never opens a browser and returns `ATLASSIAN_AUTH_REQUIRED` with the exact remediation command.
- `doctor REPO` remains governance-only; only `doctor REPO --client CLIENT` checks connector health.
- OAuth credentials remain owned by the selected client/OS keyring.
- No option, prompt, output, log, config, or environment contract accepts a developer API token.
- Tests use temporary HOME/XDG directories, fake clients, and no real credentials.
- No command creates, moves, deletes, or overwrites `v1.0.0`.

## File Map

| File | Responsibility |
| --- | --- |
| `bin/beroka-governance` | Client selection, dependency/config checks, connector setup, health normalization, OAuth delegation, connector-aware Doctor |
| `tests/connectors.sh` | Isolated fake-client tests for setup, health, prompts, remediation, and governance-only isolation |
| `README.md` | Copy-paste bootstrap and explicit client selection |
| `handbook.md` | Vietnamese client setup, OAuth, Doctor, and troubleshooting guidance |
| `PACKAGE-DESIGN.md` | Durable CLI lifecycle, failure codes, and security boundary |

---

### Task 1: Connector selection and registration

**Files:**
- Modify: `bin/beroka-governance:4-37`
- Modify: `bin/beroka-governance:719-762`
- Create: `tests/connectors.sh`

**Interfaces:**
- Consumes: `die CODE [MESSAGE]`, `assert_safe_user_path PATH LABEL`, and `apply_user_file SOURCE DESTINATION LABEL`.
- Produces: `client_executable CLIENT`, `require_client CLIENT`, `connector_state CLIENT`, `configure_connector CLIENT`, `oauth_command CLIENT`, and `cmd_setup_connectors ARGS...`.

- [ ] **Step 1: Write failing dependency and explicit-selection tests**

Create `tests/connectors.sh` with an isolated root and fake client commands:

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-connectors-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export HOME=$TEST_ROOT/home
export XDG_CONFIG_HOME=$TEST_ROOT/config
export XDG_DATA_HOME=$TEST_ROOT/data
export BEROKA_GOV_BIN_DIR=$TEST_ROOT/bin
FAKE_BIN=$TEST_ROOT/fake-bin
CALLS=$TEST_ROOT/calls
export CALLS
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$BEROKA_GOV_BIN_DIR" "$FAKE_BIN"
PATH=$FAKE_BIN:/usr/bin:/bin
export PATH

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() {
  case "$1" in *"$2"*) ;; *) fail "expected [$2] in [$1]" ;; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) fail "did not expect [$2] in [$1]" ;; *) ;; esac
}

if output=$($CLI setup-connectors --client codex --non-interactive 2>&1); then
  fail 'setup accepted missing Codex'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'

if $CLI setup-connectors --client invalid --non-interactive >/dev/null 2>&1; then
  fail 'setup accepted an unsupported client'
fi
```

- [ ] **Step 2: Run the connector test and verify RED**

Run: `sh tests/connectors.sh`

Expected: FAIL because `setup-connectors` is not present in the usage or command dispatcher.

- [ ] **Step 3: Add selection, dependency, configuration, and remediation functions**

Add the endpoint constant and usage:

```sh
ATLASSIAN_MCP_URL=https://mcp.atlassian.com/v1/mcp/authv2
```

```sh
'  beroka-governance setup-connectors [--client codex|claude|cursor] [--non-interactive]' \
'  beroka-governance doctor REPO [--client codex|claude|cursor]' \
```

Add these functions before `cmd_doctor`:

```sh
client_executable() {
  case "$1" in
    codex) printf '%s\n' codex ;;
    claude) printf '%s\n' claude ;;
    cursor) printf '%s\n' cursor-agent ;;
    *) usage >&2; exit 2 ;;
  esac
}

oauth_command() {
  case "$1" in
    codex) printf '%s\n' 'codex mcp login atlassian' ;;
    claude) printf '%s\n' 'claude mcp login atlassian' ;;
    cursor) printf '%s\n' 'cursor-agent mcp login atlassian' ;;
    *) usage >&2; exit 2 ;;
  esac
}

require_client() {
  rc_client=$1
  rc_executable=$(client_executable "$rc_client")
  command -v "$rc_executable" >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING "Missing dependency: $rc_executable"
  case "$rc_client" in
    codex)
      codex mcp login --help >/dev/null 2>&1 &&
        codex app-server --help >/dev/null 2>&1 ||
        die DEPENDENCY_MISSING 'Codex lacks required MCP/app-server commands'
      ;;
    claude)
      claude mcp login --help >/dev/null 2>&1 ||
        die DEPENDENCY_MISSING 'Claude Code lacks required MCP login support'
      ;;
    cursor)
      cursor-agent mcp login --help >/dev/null 2>&1 ||
        die DEPENDENCY_MISSING 'Cursor Agent lacks required MCP login support'
      command -v jq >/dev/null 2>&1 || die DEPENDENCY_MISSING 'Missing dependency: jq'
      ;;
  esac
}

connector_state() {
  cs_client=$1
  case "$cs_client" in
    codex)
      cs_output=$(codex mcp get atlassian --json 2>/dev/null) || return 1
      ;;
    claude)
      cs_output=$(claude mcp get atlassian 2>/dev/null) || return 1
      ;;
    cursor)
      cs_file=$HOME/.cursor/mcp.json
      [ -f "$cs_file" ] || return 1
      jq -e --arg url "$ATLASSIAN_MCP_URL" \
        '.mcpServers.atlassian.url == $url' "$cs_file" >/dev/null 2>&1 && return 0
      jq -e '.mcpServers.atlassian != null' "$cs_file" >/dev/null 2>&1 && return 2
      return 1
      ;;
  esac
  case "$cs_output" in
    *"$ATLASSIAN_MCP_URL"*) return 0 ;;
    *atlassian*) return 2 ;;
    *) return 1 ;;
  esac
}

codex_configure_atlassian() {
  cca_output=$(
    {
      printf '%s\n' \
        '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"beroka-governance","title":"Beroka Governance","version":"1"}}}' \
        '{"method":"initialized","params":{}}' \
        '{"method":"config/value/write","id":1,"params":{"keyPath":"mcp_servers.atlassian","value":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"},"mergeStrategy":"upsert"}}'
      sleep 1
    } | codex app-server --stdio 2>&1
  ) || die GOVERNANCE_NOT_READY 'Codex could not configure Atlassian MCP'
  case "$cca_output" in
    *'"id":1,"result"'*) ;;
    *) die GOVERNANCE_NOT_READY 'Codex rejected Atlassian MCP configuration' ;;
  esac
}

cursor_configure_atlassian() {
  cuca_dir=$HOME/.cursor
  cuca_file=$cuca_dir/mcp.json
  assert_safe_user_path "$cuca_dir" 'Cursor config'
  assert_safe_user_path "$cuca_file" 'Cursor MCP config'
  mkdir -p "$cuca_dir" || die GOVERNANCE_NOT_READY 'Cannot create Cursor config directory'
  cuca_temp=$(mktemp "$cuca_dir/.beroka-mcp.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot stage Cursor MCP config'
  if [ -f "$cuca_file" ]; then
    jq --arg url "$ATLASSIAN_MCP_URL" \
      '.mcpServers = (.mcpServers // {}) | .mcpServers.atlassian = {"url": $url}' \
      "$cuca_file" >"$cuca_temp" ||
      die GOVERNANCE_NOT_READY 'Cursor MCP config is invalid JSON'
  else
    printf '%s\n' '{}' | jq --arg url "$ATLASSIAN_MCP_URL" \
      '.mcpServers = {"atlassian":{"url":$url}}' >"$cuca_temp" ||
      die GOVERNANCE_NOT_READY 'Cannot stage Cursor MCP config'
  fi
  apply_user_file "$cuca_temp" "$cuca_file" 'Cursor MCP config'
  rm -f "$cuca_temp"
}

configure_connector() {
  case "$1" in
    codex) codex_configure_atlassian ;;
    claude)
      claude mcp add --transport http --scope user atlassian "$ATLASSIAN_MCP_URL" \
        >/dev/null 2>&1 || die GOVERNANCE_NOT_READY 'Claude Code could not configure Atlassian MCP'
      ;;
    cursor) cursor_configure_atlassian ;;
  esac
}
```

Implement `cmd_setup_connectors` option parsing so `--client` accepts only one
value, `--non-interactive` disables prompts, and missing `--client` outside a
TTY exits with usage status 2. Add detection with `command -v` for the three
client executables; zero returns `DEPENDENCY_MISSING`, one asks for
confirmation, and multiple print a numbered prompt and configure only the
chosen value. When a configured connector conflicts, return
`CONNECTOR_MISSING` without overwriting it.

Dispatch with:

```sh
setup-connectors) cmd_setup_connectors "${@:2}" ;;
```

Because `${@:2}` is not POSIX, implement the dispatcher as:

```sh
setup-connectors) shift; cmd_setup_connectors "$@" ;;
```

- [ ] **Step 4: Extend fake clients and verify registration GREEN**

Add fake executables that append their argv to `$CALLS`, report connector
absence/presence from files beneath `$XDG_CONFIG_HOME`, and emulate Codex
app-server config writes, Claude `mcp add`, and Cursor `jq` merges. Assert:

```sh
assert_contains "$(cat "$CALLS")" 'codex app-server --stdio'
assert_not_contains "$(cat "$CALLS")" 'mcp login atlassian'
```

Run: `sh tests/connectors.sh`

Expected: setup reaches `ATLASSIAN_AUTH_REQUIRED` in non-interactive mode after
registering exactly the selected connector.

- [ ] **Step 5: Commit selection and registration**

```bash
git add bin/beroka-governance tests/connectors.sh
git commit -m "feat: add client-selected connector setup"
```

### Task 2: Authentication health and connector-aware Doctor

**Files:**
- Modify: `bin/beroka-governance:719-762`
- Modify: `tests/connectors.sh`

**Interfaces:**
- Consumes: `require_client`, `connector_state`, and `oauth_command` from Task 1.
- Produces: `connector_health CLIENT`, `auth_required CLIENT`, and
  `cmd_doctor REPO [--client CLIENT]`.

- [ ] **Step 1: Add failing health, remediation, and Doctor tests**

Extend fake-client state so each client can report `healthy`, `auth-required`,
or `failed`. Add assertions:

```sh
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1); then
  fail 'non-interactive setup accepted missing Atlassian authentication'
fi
assert_contains "$output" 'Authentication: AUTH_REQUIRED'
assert_contains "$output" 'Remediation: codex mcp login atlassian'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

FAKE_CODEX_HEALTH=healthy
export FAKE_CODEX_HEALTH
output=$($CLI setup-connectors --client codex --non-interactive)
assert_contains "$output" 'Result: PASS'
```

Create the existing release/consumer fixtures by reusing the setup pattern from
`tests/smoke.sh`, then assert:

```sh
: >"$CALLS"
$CLI doctor "$consumer" >/dev/null
[ ! -s "$CALLS" ] || fail 'governance-only Doctor invoked a client'

if output=$($CLI doctor "$consumer" --client codex 2>&1); then
  fail 'connector-aware Doctor accepted required authentication'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
```

- [ ] **Step 2: Run the new cases and verify RED**

Run: `sh tests/connectors.sh`

Expected: FAIL because setup does not normalize auth health and Doctor accepts
only two arguments.

- [ ] **Step 3: Implement normalized health and OAuth delegation**

Add:

```sh
connector_health() {
  ch_client=$1
  case "$ch_client" in
    codex)
      ch_output=$(
        {
          printf '%s\n' \
            '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"beroka-governance","title":"Beroka Governance","version":"1"}}}' \
            '{"method":"initialized","params":{}}' \
            '{"method":"mcpServerStatus/list","id":1,"params":{"detail":"toolsAndAuthOnly","limit":1}}'
          sleep 3
        } | codex app-server --stdio 2>&1
      ) || return 2
      case "$ch_output" in
        *'"name":"atlassian"'*'"authStatus":"notLoggedIn"'*|\
        *'"failureReason":"reauthenticationRequired"'*|\
        *'unauthorized_client'*|*'401 Unauthorized'*|*'403 Forbidden'*) return 1 ;;
        *'"name":"atlassian"'*'atlassianUserInfo'*) return 0 ;;
        *) return 2 ;;
      esac
      ;;
    claude)
      ch_output=$(claude mcp list 2>&1) || :
      case "$ch_output" in
        *atlassian*Connected*|*atlassian*connected*) return 0 ;;
        *atlassian*authentication*|*atlassian*Authentication*|*atlassian*401*|*atlassian*403*) return 1 ;;
        *) return 2 ;;
      esac
      ;;
    cursor)
      ch_output=$(cursor-agent mcp list 2>&1) || :
      case "$ch_output" in
        *atlassian*ready*)
          cursor-agent mcp list-tools atlassian >/dev/null 2>&1 && return 0
          return 2
          ;;
        *atlassian*auth*|*atlassian*login*) return 1 ;;
        *) return 2 ;;
      esac
      ;;
  esac
}

auth_required() {
  ar_client=$1
  printf '%s\n' \
    "Client: $ar_client" \
    'Authentication: AUTH_REQUIRED' \
    "Remediation: $(oauth_command "$ar_client")"
  die ATLASSIAN_AUTH_REQUIRED
}
```

Complete `cmd_setup_connectors`:

```sh
setup_health=0
connector_health "$setup_client" || setup_health=$?
if [ "$setup_health" -eq 0 ]; then
  printf '%s\n' "Client: $setup_client" 'Result: PASS'
  return
fi
[ "$setup_health" -eq 1 ] ||
  die GOVERNANCE_NOT_READY "Cannot verify $setup_client Atlassian connector health"
printf '%s\n' "Client: $setup_client" 'Authentication: AUTH_REQUIRED'
if [ "$setup_interactive" -eq 1 ]; then
  printf 'Start OAuth now? [y/N] '
  IFS= read -r setup_answer || setup_answer=
  case "$setup_answer" in
    y|Y|yes|YES)
      case "$setup_client" in
        codex) codex mcp login atlassian ;;
        claude) claude mcp login atlassian ;;
        cursor) cursor-agent mcp login atlassian ;;
      esac
      connector_health "$setup_client" ||
        auth_required "$setup_client"
      printf '%s\n' "Client: $setup_client" 'Result: PASS'
      return
      ;;
  esac
fi
auth_required "$setup_client"
```

Extend Doctor:

```sh
cmd_doctor() {
  requested=$1 client_flag=${2:-} doctor_client=${3:-}
  [ -z "$client_flag" ] || {
    [ "$client_flag" = --client ] && [ -n "$doctor_client" ] ||
      { usage >&2; exit 2; }
  }
  verify_registration "$requested"
  if [ -n "$doctor_client" ]; then
    require_client "$doctor_client"
    connector_state "$doctor_client"
    doctor_connector=$?
    [ "$doctor_connector" -eq 0 ] ||
      die CONNECTOR_MISSING "Missing compatible Atlassian connector for $doctor_client"
    doctor_health=0
    connector_health "$doctor_client" || doctor_health=$?
    if [ "$doctor_health" -ne 0 ]; then
      [ "$doctor_health" -eq 1 ] && auth_required "$doctor_client"
      die GOVERNANCE_NOT_READY "Cannot verify $doctor_client Atlassian connector health"
    fi
    printf '%s\n' "Client: $doctor_client" 'Connector: PASS' 'Authentication: PASS'
  fi
  printf '%s\n' "Repository: $LOCK_REPOSITORY" "Version: $LOCK_VERSION" "Commit: $LOCK_COMMIT" 'Result: PASS'
}
```

Update Doctor dispatch to accept either two or four arguments.

- [ ] **Step 4: Verify GREEN and the existing lifecycle**

Run:

```bash
sh -n bin/beroka-governance
sh tests/connectors.sh
sh tests/smoke.sh
```

Expected: all three commands exit 0; connector tests print their PASS lines and
the existing smoke test retains all lifecycle PASS lines.

- [ ] **Step 5: Commit health and Doctor**

```bash
git add bin/beroka-governance tests/connectors.sh
git commit -m "feat: check client connector authentication"
```

### Task 3: Bootstrap and operator documentation

**Files:**
- Modify: `README.md:7-31`
- Modify: `handbook.md:57-90`
- Modify: `handbook.md:124-204`
- Modify: `handbook.md:377-395`
- Modify: `PACKAGE-DESIGN.md:133-175`
- Modify: `PACKAGE-DESIGN.md:251-275`

**Interfaces:**
- Consumes: final CLI syntax and result codes from Tasks 1-2.
- Produces: one documented setup/remediation path for each client and no
  API-token path for Atlassian.

- [ ] **Step 1: Add documentation assertions before editing docs**

Add to `tests/connectors.sh`:

```sh
for document in "$ROOT/README.md" "$ROOT/handbook.md" "$ROOT/PACKAGE-DESIGN.md"; do
  grep -F 'setup-connectors' "$document" >/dev/null ||
    fail "missing setup-connectors documentation in $document"
done
grep -F 'codex mcp login atlassian' "$ROOT/handbook.md" >/dev/null ||
  fail 'missing Codex remediation command'
grep -F 'ATLASSIAN_AUTH_REQUIRED' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fail 'missing authentication result in package design'
```

- [ ] **Step 2: Run the documentation assertions and verify RED**

Run: `sh tests/connectors.sh`

Expected: FAIL on the first missing `setup-connectors` reference.

- [ ] **Step 3: Update the bootstrap and client guidance**

Update README quick start to include one selected client:

```bash
client=codex
sh "$bootstrap_dir/repo/bin/beroka-governance" install "$release"
beroka-governance setup-connectors --client "$client"
beroka-governance register /srv/beroka/backend --version "$release"
beroka-governance doctor /srv/beroka/backend
beroka-governance doctor /srv/beroka/backend --client "$client"
```

Update the handbook with:

```bash
beroka-governance setup-connectors --client codex
beroka-governance setup-connectors --client claude
beroka-governance setup-connectors --client cursor
```

State that each command configures only its explicit client, can be rerun for a
second client, and uses these remediation commands:

```bash
codex mcp login atlassian
claude mcp login atlassian
cursor-agent mcp login atlassian
```

Remove the Atlassian developer API-token path and retain unrelated GitHub
guidance. Document `--non-interactive`, `DEPENDENCY_MISSING`,
`CONNECTOR_MISSING`, and `ATLASSIAN_AUTH_REQUIRED`.

Add Setup Connectors and connector-aware Doctor lifecycle sections plus the
three result codes to `PACKAGE-DESIGN.md`. Keep the existing statement that a
release tag is never moved or reused.

- [ ] **Step 4: Run the complete release gate**

Run:

```bash
sh -n bin/beroka-governance
sh tests/smoke.sh
sh tests/connectors.sh
git diff --check
test "$(git rev-parse refs/tags/v1.0.0)" = 1f2db6bd75cf9d9a68d501c351fb2455448e04e1
```

Expected: every command exits 0 and the `v1.0.0` tag object remains
`1f2db6bd75cf9d9a68d501c351fb2455448e04e1`.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md handbook.md PACKAGE-DESIGN.md tests/connectors.sh
git commit -m "docs: add connector setup rollout"
```
