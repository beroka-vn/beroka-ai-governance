# Atlassian Re-authentication Hotfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect Codex's current expired-refresh-token error and make interactive Atlassian re-authentication run immediately through the selected producer while preserving non-interactive behavior.

**Architecture:** Extend the existing shared Codex authentication classifier with one narrowly scoped runtime-log match, then keep all setup, bootstrap, Doctor, preflight, and Cursor-hook callers on the existing `connector_health` boundary. Remove only the optional Atlassian OAuth confirmations, update Claude's existing producer command at the OAuth boundary, and teach managed agents how to recover from non-interactive authentication failures.

**Tech Stack:** POSIX shell, awk, grep, Codex/Claude Code/Cursor Agent CLIs, existing shell test harness, Markdown

## Global Constraints

- Target Issue #36 only.
- Match the current Codex refresh error only when the line contains `codex_rmcp_client::oauth::refresh_transaction`, `server atlassian`, `unauthorized_client`, and `refresh_token is invalid`.
- An authenticated Codex response with `authStatus: "oAuth"` and `tools: {}` remains a complete empty inventory and `UNSUPPORTED`.
- Interactive Atlassian setup and preflight start the selected producer's OAuth flow immediately after authentication is classified as required.
- Cursor first-run retains its existing global-configuration confirmation and receives no second OAuth confirmation.
- Non-interactive setup, bootstrap, preflight, Doctor, and Cursor hooks never launch OAuth or block for input.
- Codex uses `codex mcp login atlassian`; Cursor uses `cursor-agent mcp login atlassian`; Claude uses `claude mcp login atlassian --no-browser`.
- Check Claude `--no-browser` support only when `run_oauth claude` is about to execute; do not add a general version parser.
- An unsupported Claude OAuth command fails closed with `DEPENDENCY_MISSING` and `Remediation: claude update`.
- Producer output stays attached to the terminal; governance never synthesizes, parses, persists, or copies the one-time URL into an issue, commit, or durable log.
- Do not change the Atlassian capability registry, accept developer API tokens, alter application repositories, or update release metadata.

---

### Task 1: Classify the current Codex refresh failure

**Files:**
- Modify: `tests/connectors.sh:180-435,1400-1430,1560-1615`
- Modify: `tests/routing.sh:90-430,1245-1275,1660-1710`
- Modify: `bin/beroka-governance:1816-2075,2817-2975`

**Interfaces:**
- Consumes: the complete Codex app-server probe captured in `CONNECTOR_PROBE_OUTPUT`.
- Produces: `codex_http_auth_required` returning success for the exact refresh-transaction error before `connector_health`, `connector_inventory`, or capability resolution reduces the status response.

- [ ] **Step 1: Add the current Codex refresh fixture**

Add this case to both fake Codex app-server implementations:

```sh
refresh-token-invalid)
  printf '%s\n' \
    '2026-07-31T03:04:05.000Z ERROR codex_rmcp_client::oauth::refresh_transaction: error=failed to refresh OAuth tokens for server atlassian: OAuth token refresh failed: Server returned error response: unauthorized_client: refresh_token is invalid' \
    '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
  ;;
```

Add one scoped negative fixture to `tests/routing.sh`:

```sh
refresh-token-invalid-other-server)
  printf '%s\n' \
    '2026-07-31T03:04:05.000Z ERROR codex_rmcp_client::oauth::refresh_transaction: error=failed to refresh OAuth tokens for server github: OAuth token refresh failed: Server returned error response: unauthorized_client: refresh_token is invalid' \
    '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
  ;;
```

- [ ] **Step 2: Write the failing connector and Doctor assertions**

In `tests/connectors.sh`, exercise the shared health boundary:

```sh
printf '%s\n' refresh-token-invalid \
  >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fail 'Codex refresh-token failure passed connector setup'
fi
assert_contains "$output" 'Remediation: codex mcp login atlassian'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

: >"$CALLS"
if output=$($CLI doctor "$CONSUMER" --client codex 2>&1); then
  fail 'Doctor accepted the Codex refresh-token failure'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
```

Keep the existing `healthy-empty-tools` Doctor assertions unchanged; they must
still report `Authentication: PASS`.

- [ ] **Step 3: Write the failing routing assertions**

Add this regression beside the existing Codex 401/403 cases:

```sh
printf '%s\n' refresh-token-invalid \
  >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'Codex refresh-token failure passed Jira preflight'
fi
assert_contains "$output" 'Remediation: codex mcp login atlassian'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'CONNECTOR_CAPABILITY_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
```

Prove the match remains Atlassian-scoped:

```sh
printf '%s\n' refresh-token-invalid-other-server \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'authenticated empty inventory passed Jira preflight'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
```

Keep the existing plain `healthy-empty-tools` preflight assertions unchanged.

- [ ] **Step 4: Run the tests to verify RED**

Run:

```bash
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: both suites exit nonzero because the timestamped refresh error is
discarded and the trailing `oAuth` empty inventory is still treated as healthy.

- [ ] **Step 5: Extend the shared classifier minimally**

Change only `codex_http_auth_required`:

```sh
codex_http_auth_required() {
  awk '
    {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      if ((line ~ /^server atlassian:/ &&
           (line ~ /unauthorized_client/ ||
            line ~ /401 Unauthorized/ ||
            line ~ /403 Forbidden/)) ||
          (line ~ /codex_rmcp_client::oauth::refresh_transaction/ &&
           line ~ /server atlassian:/ &&
           line ~ /unauthorized_client/ &&
           line ~ /refresh_token is invalid/)) found=1
    }
    END { exit !found }
  '
}
```

Do not move classification after `codex_atlassian_record`; the full runtime
log must remain available to `codex_probe_complete`,
`codex_connector_probe`, and `connector_health`.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run:

```bash
sh -n bin/beroka-governance
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: all commands exit `0`; the refresh fixture returns
`ATLASSIAN_AUTH_REQUIRED`, while both empty-inventory fixtures without the
exact Atlassian error remain authenticated and unsupported.

- [ ] **Step 7: Commit the classifier**

```bash
git add bin/beroka-governance tests/connectors.sh tests/routing.sh
git commit -m "fix: classify Codex Atlassian refresh failures"
```

### Task 2: Start producer-owned Atlassian OAuth automatically

**Files:**
- Modify: `tests/connectors.sh:960-1045,1400-1500`
- Modify: `tests/routing.sh:90-120,450-515,1660-1745`
- Modify: `bin/beroka-governance:1413-1465,2985-3000,3271-3295,3435-3630`

**Interfaces:**
- Consumes: `connector_health CLIENT`, the existing interactive TTY checks, `run_oauth CLIENT`, and cached `CONNECTOR_PROBE_*` state.
- Produces: `oauth_command claude` as `claude mcp login atlassian --no-browser`; `run_oauth claude` with a boundary-local help check; immediate interactive OAuth in `cmd_setup_connectors` and `cmd_preflight`.

- [ ] **Step 1: Extend fake producer commands**

In both connector and routing fake Claude executables, add:

```sh
'mcp login --help')
  [ "${FAKE_CLAUDE_NO_BROWSER:-1}" -eq 1 ] &&
    printf '%s\n' 'Usage: claude mcp login [options] <name>' \
      '  --no-browser  Print the authentication URL'
  ;;
'mcp login atlassian --no-browser')
  printf '%s\n' \
    'OAuth URL: https://auth.example.test/claude-one-time'
  printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
  ;;
```

Make the fake Codex login emit its existing one-time URL and set healthy state;
keep the fake Cursor login behavior and neutral `/` working directory intact.

- [ ] **Step 2: Replace optional-prompt tests with automatic setup tests**

In `tests/connectors.sh`, run interactive Codex setup with no `y` answer:

```sh
printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
output=$(script -qec \
  "$CLI setup-connectors --client codex" /dev/null 2>&1)
assert_contains "$output" \
  'OAuth URL: https://auth.example.test/authorize?state=one-time'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'Start OAuth now?'
assert_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
```

Keep and rerun the existing non-interactive assertions proving no login,
Doctor assertions proving no login, Cursor first-run confirmation, Cursor
neutral-directory assertions, failed-login handling, post-login health
verification, and OAuth URL non-persistence.

- [ ] **Step 3: Write Claude direct-login and fail-closed tests**

Add these connector cases:

```sh
printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-claude-health"
: >"$CALLS"
output=$(script -qec \
  "$CLI setup-connectors --client claude" /dev/null 2>&1)
assert_contains "$output" \
  'OAuth URL: https://auth.example.test/claude-one-time'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'Start OAuth now?'
assert_contains "$(cat "$CALLS")" \
  'claude mcp login atlassian --no-browser'
grep -Fx 'claude mcp login atlassian --no-browser' "$CALLS" >/dev/null ||
  fail 'interactive Claude setup did not use direct no-browser login'

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-claude-health"
: >"$CALLS"
if output=$(FAKE_CLAUDE_NO_BROWSER=0 script -qec \
  "$CLI setup-connectors --client claude" /dev/null 2>&1)
then
  fail 'Claude without --no-browser support started OAuth'
fi
assert_contains "$output" 'Remediation: claude update'
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
assert_not_contains "$(cat "$CALLS")" \
  'claude mcp login atlassian --no-browser'
```

Also update the existing non-interactive Claude assertion to require:

```sh
assert_contains "$output" \
  'Remediation: claude mcp login atlassian --no-browser'
assert_not_contains "$(cat "$CALLS")" \
  'claude mcp login atlassian --no-browser'
```

- [ ] **Step 4: Write automatic preflight assertions**

Replace the Codex decline/accept cases in `tests/routing.sh` with:

```sh
printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
output=$(script -qec \
  "$CLI preflight $consumer --client codex --operation jira-write" \
  /dev/null 2>&1)
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'Start OAuth now?'
assert_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
assert_not_contains "$(cat "$CALLS")" 'claude mcp login atlassian'
assert_not_contains "$(cat "$CALLS")" \
  'cursor-agent mcp login atlassian'
```

Keep the existing non-interactive preflight test unchanged and retain the
post-login unclassifiable-health failure. Run `tests/cursor-hooks.sh` later to
prove its `cmd_preflight ... --non-interactive` path remains unattended.

- [ ] **Step 5: Run the focused tests to verify RED**

Run:

```bash
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: both suites exit nonzero because setup and preflight still print
`Start OAuth now?`; Claude still launches the plain client and has no
`--no-browser` support gate.

- [ ] **Step 6: Implement the producer commands and boundary-local support check**

Update the remediation command:

```sh
oauth_command() {
  case "$1" in
    codex) printf '%s\n' 'codex mcp login atlassian' ;;
    claude)
      printf '%s\n' 'claude mcp login atlassian --no-browser'
      ;;
    cursor) printf '%s\n' 'cursor-agent mcp login atlassian' ;;
    *) usage >&2; exit 2 ;;
  esac
}
```

Replace only the Claude branch of `run_oauth`:

```sh
claude)
  claude mcp login --help 2>&1 |
    grep -F -- '--no-browser' >/dev/null ||
    die DEPENDENCY_MISSING 'Remediation: claude update'
  claude mcp login atlassian --no-browser
  ;;
```

Remove the obsolete `In Claude: /mcp -> atlassian -> Authenticate` lines from
`auth_required` and `auth_pending`. Do not add the support check to
`require_client`; non-interactive and Doctor paths must not acquire a new OAuth
probe.

- [ ] **Step 7: Remove only the optional Atlassian OAuth confirmations**

In `cmd_setup_connectors`, preserve the TTY calculation but replace the
`Start OAuth now?` branch with:

```sh
[ "$setup_interactive" -eq 1 ] ||
  auth_required "$setup_client"
printf '%s\n' \
  "Client: $setup_client" \
  'Provider: atlassian' \
  'Authentication: AUTH_REQUIRED'
run_oauth "$setup_client" || auth_pending "$setup_client"
setup_health=0
connector_health "$setup_client" || setup_health=$?
case "$setup_health" in
  0) ;;
  1) auth_pending "$setup_client" ;;
  *) connector_health_unavailable "$setup_client" ;;
esac
printf '%s\n' \
  "Client: $setup_client" \
  'Connector: PASS' \
  'Authentication: PASS'
pass_result
```

In `cmd_preflight`, preserve routing, role, connector, TTY, and
non-interactive checks; replace only the optional-answer branch:

```sh
if [ "$pf_health" -eq 1 ]; then
  pf_interactive=0
  if [ "$pf_non_interactive" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    pf_interactive=1
  fi
  [ "$pf_interactive" -eq 1 ] ||
    auth_required "$pf_client"
  printf '%s\n' \
    "Client: $pf_client" \
    'Provider: atlassian' \
    'Authentication: AUTH_REQUIRED'
  run_oauth "$pf_client" || auth_required "$pf_client"
  pf_health=0
  connector_health "$pf_client" || pf_health=$?
  case "$pf_health" in
    0) ;;
    1) auth_required "$pf_client" ;;
    *) connector_health_unavailable "$pf_client" ;;
  esac
elif [ "$pf_health" -ne 0 ]; then
  connector_health_unavailable "$pf_client"
fi
```

Leave `github_preflight` unchanged. Leave `cursor_first_run_setup`'s
`Install global Atlassian MCP and start OAuth now? [y/N]` configuration-write
confirmation unchanged.

- [ ] **Step 8: Run focused tests to verify GREEN**

Run:

```bash
sh -n bin/beroka-governance
sh tests/connectors.sh
sh tests/routing.sh
sh tests/bootstrap.sh
sh tests/cursor-hooks.sh
```

Expected: all commands exit `0`; interactive setup/preflight stream producer
output without the optional OAuth prompt, non-interactive and Doctor never
login, bootstrap inherits the setup behavior, and Cursor hooks remain
non-interactive.

- [ ] **Step 9: Commit the producer-owned flow**

```bash
git add bin/beroka-governance tests/connectors.sh tests/routing.sh
git commit -m "fix: run required Atlassian OAuth directly"
```

### Task 3: Add managed-agent handoff and producer guidance

**Files:**
- Modify: `templates/agent-entrypoints/AGENTS.md`
- Modify: `templates/agent-entrypoints/CLAUDE.md`
- Modify: `templates/agent-entrypoints/CURSOR-USER-RULE.txt`
- Modify: `tests/bootstrap.sh:35-70,360-790`
- Modify: `README.md:40-52,120-145`
- Modify: `handbook.md:105-165`
- Modify: `PACKAGE-DESIGN.md:35-65,115-160`

**Interfaces:**
- Consumes: `ATLASSIAN_AUTH_REQUIRED`, the exact selected-client remediation,
  producer-owned terminal output, and operation-specific preflight.
- Produces: identical mandatory recovery instructions for active Codex, Claude,
  and Cursor agents plus user-facing producer guidance.

- [ ] **Step 1: Write failing managed-template assertions**

Add this helper to `tests/bootstrap.sh`:

```sh
assert_atlassian_auth_handoff() {
  aah_file=$1 aah_command=$2
  grep -F 'ATLASSIAN_AUTH_REQUIRED' "$aah_file" >/dev/null ||
    fail "missing Atlassian auth handoff in $aah_file"
  grep -F "$aah_command" "$aah_file" >/dev/null ||
    fail "missing producer login command in $aah_file"
  grep -F 'stream the producer output' "$aah_file" >/dev/null ||
    fail "missing producer-output rule in $aah_file"
  grep -F 'never synthesize, parse, persist, or place that URL' \
    "$aah_file" >/dev/null ||
    fail "missing one-time URL handling rule in $aah_file"
  grep -F 'fresh operation-specific preflight' "$aah_file" >/dev/null ||
    fail "missing fresh-preflight rule in $aah_file"
  grep -F 'Result: PASS' "$aah_file" >/dev/null ||
    fail "missing PASS continuation boundary in $aah_file"
}
```

After the corresponding bootstrap cases, call it for the installed Codex and
Claude managed instruction files:

```sh
assert_atlassian_auth_handoff \
  "$HOME/.codex/AGENTS.md" \
  'codex mcp login atlassian'
assert_atlassian_auth_handoff \
  "$HOME/.claude/CLAUDE.md" \
  'claude mcp login atlassian --no-browser'
```

For Cursor, assert the interactive bootstrap output contains the complete
handoff boundary emitted from `CURSOR-USER-RULE.txt`:

```sh
assert_contains "$cursor_output" 'ATLASSIAN_AUTH_REQUIRED'
assert_contains "$cursor_output" 'cursor-agent mcp login atlassian'
assert_contains "$cursor_output" 'stream the producer output'
assert_contains "$cursor_output" \
  'never synthesize, parse, persist, or place that URL'
assert_contains "$cursor_output" 'fresh operation-specific preflight'
assert_contains "$cursor_output" 'Result: PASS'
```

- [ ] **Step 2: Run installed-artifact tests to verify RED**

Run:

```bash
sh tests/bootstrap.sh
```

Expected: the suite exits nonzero because installed managed instructions and
the emitted Cursor User Rule lack the mandatory handoff.

- [ ] **Step 3: Add the mandatory handoff to all three templates**

Add this wording to `templates/agent-entrypoints/AGENTS.md` after the
fresh-preflight rule:

```markdown
If a non-interactive preflight returns `ATLASSIAN_AUTH_REQUIRED`, stop the
dependent external write. In an interactive terminal, run
`codex mcp login atlassian` and stream the producer output so the user can open its
one-time URL. Never synthesize, parse, persist, or place that URL in an issue,
commit, or durable log. Then rerun a fresh operation-specific preflight and
continue only when it returns `Result: PASS`.
```

Add the same paragraph to `templates/agent-entrypoints/CLAUDE.md` with this
command sentence:

```markdown
In an interactive terminal, run
`claude mcp login atlassian --no-browser` and stream the producer output so
the user can open its one-time URL.
```

Add the same paragraph to
`templates/agent-entrypoints/CURSOR-USER-RULE.txt` with this command sentence:

```markdown
In an interactive terminal, run `cursor-agent mcp login atlassian` and stream
the producer output so the user can open its one-time URL.
```

- [ ] **Step 4: Update active producer documentation**

Document these exact behaviors in `README.md`, `handbook.md`, and
`PACKAGE-DESIGN.md`:

- once Atlassian authentication is known to be missing, expired, or invalid,
  interactive setup/bootstrap/preflight start re-authentication immediately;
- Codex, Claude, and Cursor use the three exact producer commands above;
- Claude validates `--no-browser` with `claude mcp login --help` only at the
  OAuth boundary and otherwise returns `DEPENDENCY_MISSING` with
  `Remediation: claude update`;
- non-interactive and Doctor paths never invoke login, and Cursor hooks retain
  their non-interactive preflight contract;
- the active agent stops the dependent write, streams producer output, never
  synthesizes, parses, persists, or copies the URL to durable artifacts, then
  reruns a fresh operation-specific preflight and continues only on
  `Result: PASS`;
- Cursor first-run still requires its existing global-MCP configuration
  confirmation before OAuth starts.

Do not add release-version, tag, changelog, manifest, or publication changes.

- [ ] **Step 5: Run focused instruction and documentation checks**

Run:

```bash
sh tests/bootstrap.sh
sh tests/documentation-architecture.sh
sh tests/release.sh
git diff --check
```

Expected: all commands exit `0`; installed managed instructions preserve
personal content and contain the client-specific handoff, Cursor emits the
same boundary, and the existing documentation architecture remains valid.

- [ ] **Step 6: Commit instructions and documentation**

```bash
git add templates/agent-entrypoints/AGENTS.md \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  tests/bootstrap.sh \
  README.md handbook.md PACKAGE-DESIGN.md
git commit -m "docs: require Atlassian reauthentication handoff"
```

### Task 4: Verify the complete hotfix

**Files:**
- Verify only: `bin/beroka-governance`
- Verify only: `tests/*.sh`
- Verify only: `templates/agent-entrypoints/*`
- Verify only: `README.md`, `handbook.md`, `PACKAGE-DESIGN.md`

**Interfaces:**
- Consumes: Tasks 1-3 at their committed SHAs.
- Produces: focused and complete local evidence without release or external writes.

- [ ] **Step 1: Run syntax and focused regression gates**

```bash
dash -n bin/beroka-governance tests/bootstrap.sh tests/connectors.sh \
  tests/cursor-hooks.sh tests/documentation-architecture.sh \
  tests/launcher.sh tests/release.sh tests/routing.sh tests/smoke.sh
sh tests/connectors.sh
sh tests/routing.sh
sh tests/bootstrap.sh
sh tests/cursor-hooks.sh
sh tests/documentation-architecture.sh
sh tests/release.sh
```

Expected: every command exits `0`.

- [ ] **Step 2: Run the complete local suite**

```bash
for test_file in tests/*.sh; do
  sh "$test_file"
done
```

Expected: all eight shell suites exit `0`.

- [ ] **Step 3: Audit scope and release exclusions**

```bash
git diff --check origin/main...HEAD
git diff --name-only origin/main...HEAD
git status --short
```

Expected: no whitespace errors; changes are limited to the CLI, focused tests,
three managed templates, active producer docs, the approved design, and this
plan. `VERSION`, release launchers, release manifests, compatibility registry,
tags, and application repositories are absent from the diff.
