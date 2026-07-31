# Cursor First-Run Global MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make first-time interactive Cursor connector setup install the global
Atlassian MCP entry and reach OAuth before health classification.

**Architecture:** Keep the existing file-backed global Cursor connector and
shared OAuth/health functions. Add one Cursor-only first-run gate in
`cmd_setup_connectors`: inspect the current repository only for an informational
project-MCP notice, require one interactive confirmation, configure the global
entry, run OAuth immediately, and then rejoin the normal health check.

**Tech Stack:** POSIX shell, Git, Cursor Agent CLI, jq, Markdown, existing shell
test suite

## Global Constraints

- Target Issue #30 only; do not combine Issue #31 implementation.
- Global Cursor MCP remains `~/.cursor/mcp.json`.
- Never scan other repositories or edit project-local `.cursor/mcp.json`.
- Non-interactive first-run never writes config or starts OAuth.
- Existing compatible global connectors remain idempotent.
- Existing conflicting global connectors and post-login unknown health remain
  fail-closed.
- Cursor MCP inspection and `cursor-agent mcp login atlassian` run from `/`
  through the existing `cursor_mcp`/`run_oauth` path.
- Provider OAuth output stays attached to the terminal and is never persisted.
- Add no daemon, proxy, dependency, token path, or Cursor settings-database
  write.
- Do not tag or release `v1.0.4`; Issue #31 must be handled separately first.

---

### Task 1: Cursor first-run global connector and OAuth gate

**Files:**
- Modify: `tests/connectors.sh:1179-1257,1317-1346`
- Modify: `bin/beroka-governance:1524-1620,3388-3468`

**Interfaces:**
- Consumes: `assert_safe_user_path`, `cursor_configure_atlassian`,
  `run_oauth`, `connector_health`, `auth_pending`,
  `connector_health_unavailable`, and `pass_result`.
- Produces: `cursor_project_mcp_notice`,
  `cursor_global_connector_required`, `cursor_first_run_setup`, and the local
  `setup_cursor_first_run` flag in `cmd_setup_connectors`.

- [ ] **Step 1: Extend the fake Cursor boundary**

Change the fake `cursor-agent` login branch so it exposes provider output and
can preserve an unknown post-login state:

```sh
'mcp login atlassian')
  printf '%s\n' \
    'OAuth URL: https://auth.example.test/cursor-first-run'
  case "$(sed -n '1p' \
    "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)" in
    login-failed) exit 1 ;;
    post-login-unknown) ;;
    *) printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health" ;;
  esac
  ;;
```

Add `first-run-unknown|post-login-unknown` to `mcp list` with no Atlassian
status line so `connector_health cursor` returns unknown.

- [ ] **Step 2: Write the failing first-run tests**

Replace the current non-interactive expectation that setup writes the global
file. Cover these exact cases in `tests/connectors.sh`:

```sh
global_cursor_file=$HOME/.cursor/mcp.json
printf '%s\n' '{"other":{"preserved":true}}' >"$global_cursor_file"
global_before=$(cat "$global_cursor_file")
: >"$CALLS"
if output=$($CLI setup-connectors --client cursor \
  --non-interactive 2>&1)
then
  fail 'non-interactive Cursor first-run passed without global MCP'
fi
assert_contains "$output" \
  'Remediation: beroka-governance setup-connectors --client cursor'
[ "$(cat "$global_cursor_file")" = "$global_before" ] ||
  fail 'non-interactive Cursor first-run changed global MCP'
assert_not_contains "$(cat "$CALLS")" 'mcp login atlassian'
```

Create a temporary Git repository with a project-only Atlassian entry, run the
same non-interactive command from it, and assert:

```sh
assert_contains "$output" 'Project MCP: PRESENT_IGNORED'
[ "$(cat "$project_cursor_file")" = "$project_before" ] ||
  fail 'Cursor setup changed project MCP'
[ "$(cat "$global_cursor_file")" = "$global_before" ] ||
  fail 'project MCP caused a global write'
```

For interactive first-run, set `fake-cursor-health=first-run-unknown`, answer
`y` through `script`, and require:

```sh
assert_contains "$output" \
  'Install global Atlassian MCP and start OAuth now? [y/N]'
assert_contains "$output" \
  'OAuth URL: https://auth.example.test/cursor-first-run'
assert_contains "$output" 'Result: PASS'
jq -e '.other.preserved == true' "$global_cursor_file" >/dev/null ||
  fail 'Cursor first-run discarded unrelated global JSON'
jq -e --arg url 'https://mcp.atlassian.com/v1/mcp/authv2' \
  '.mcpServers.atlassian.url == $url' "$global_cursor_file" >/dev/null ||
  fail 'Cursor first-run omitted the global Atlassian MCP'
```

Compare call line numbers to prove `mcp login atlassian` occurs before the first
`mcp list`. Add decline, invalid-global-JSON, login-failure, and
post-login-unknown cases:

```sh
assert_contains "$decline_output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_contains "$invalid_output" 'Result: GOVERNANCE_NOT_READY'
assert_contains "$login_failed_output" 'Result: AUTH_PENDING'
assert_contains "$post_login_output" \
  'Result: CONNECTOR_HEALTH_UNAVAILABLE'
```

Keep the existing healthy-global, wrong-URL, neutral-directory, and OAuth
non-persistence assertions.

- [ ] **Step 3: Run the connector suite to verify RED**

Run:

```bash
sh tests/connectors.sh
```

Expected: FAIL because current non-interactive setup mutates the global file and
the interactive unknown state exits with `CONNECTOR_HEALTH_UNAVAILABLE` before
OAuth.

- [ ] **Step 4: Add the minimal Cursor-only helpers**

Add these helpers next to `cursor_configure_atlassian`:

```sh
cursor_project_mcp_notice() {
  cpmp_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  cpmp_file=$cpmp_root/.cursor/mcp.json
  [ "$cpmp_file" != "$HOME/.cursor/mcp.json" ] || return 0
  [ -f "$cpmp_file" ] && [ ! -L "$cpmp_file" ] || return 0
  jq -e '.mcpServers.atlassian != null' "$cpmp_file" \
    >/dev/null 2>&1 || return 0
  printf '%s\n' 'Project MCP: PRESENT_IGNORED'
}

cursor_global_connector_required() {
  printf '%s\n' \
    'Client: cursor' \
    'Provider: atlassian' \
    'Authentication: AUTH_REQUIRED' \
    'Remediation: beroka-governance setup-connectors --client cursor'
  die ATLASSIAN_AUTH_REQUIRED
}

cursor_first_run_setup() {
  cfr_interactive=$1
  cfr_dir=$HOME/.cursor
  cfr_file=$cfr_dir/mcp.json
  assert_safe_user_path "$cfr_dir" 'Cursor config'
  assert_safe_user_path "$cfr_file" 'Cursor MCP config'
  if [ -e "$cfr_file" ]; then
    [ -f "$cfr_file" ] && [ ! -L "$cfr_file" ] &&
      jq -e 'type == "object"' "$cfr_file" >/dev/null 2>&1 ||
      die GOVERNANCE_NOT_READY 'Cursor MCP config is invalid JSON'
  fi
  cursor_project_mcp_notice
  [ "$cfr_interactive" -eq 1 ] ||
    cursor_global_connector_required
  printf 'Install global Atlassian MCP and start OAuth now? [y/N] '
  IFS= read -r cfr_answer || cfr_answer=
  case "$cfr_answer" in
    y|Y|yes|YES)
      cursor_configure_atlassian
      run_oauth cursor || auth_pending cursor
      ;;
    *) cursor_global_connector_required ;;
  esac
}
```

Do not add a general abstraction: this behavior is valid only when the Cursor
global connector is missing.

- [ ] **Step 5: Route only missing Cursor state through the helper**

In `cmd_setup_connectors`, initialize `setup_cursor_first_run=0` and replace
the missing-connector branch with:

```sh
1)
  if [ "$setup_client" = cursor ]; then
    setup_cursor_first_run=1
    cursor_first_run_setup "$setup_interactive"
  else
    configure_connector "$setup_client"
  fi
  ;;
```

After the first health check, make a post-login authentication-required result
return `AUTH_PENDING` without prompting a second time:

```sh
1)
  [ "$setup_cursor_first_run" -eq 0 ] ||
    auth_pending "$setup_client"
  ;;
```

Leave the existing healthy, conflicting-URL, existing-auth-required, Codex, and
Claude paths unchanged.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run:

```bash
sh -n bin/beroka-governance
sh tests/connectors.sh
sh tests/bootstrap.sh
```

Expected: all commands exit `0`; first-run OAuth occurs before the first health
probe and existing connector paths remain unchanged.

- [ ] **Step 7: Commit the runtime fix**

```bash
git add bin/beroka-governance tests/connectors.sh
git commit -m "fix: complete Cursor first-run OAuth"
```

### Task 2: Document first-run and automation behavior

**Files:**
- Modify: `tests/documentation-architecture.sh`
- Modify: `README.md:40-44`
- Modify: `handbook.md:117-129`
- Modify: `PACKAGE-DESIGN.md:110-124`

**Interfaces:**
- Consumes: Task 1 result codes and prompt behavior.
- Produces: active user guidance that distinguishes interactive first-run from
  non-interactive automation.

- [ ] **Step 1: Write failing documentation assertions**

Add:

```sh
require_text README.md \
  'Install global Atlassian MCP and start OAuth now?'
require_text handbook.md 'Project MCP: PRESENT_IGNORED'
require_text PACKAGE-DESIGN.md \
  'Non-interactive Cursor first-run does not write global MCP configuration'
```

- [ ] **Step 2: Run the documentation test to verify RED**

Run:

```bash
sh tests/documentation-architecture.sh
```

Expected: FAIL because active documentation does not describe the new first-run
gate.

- [ ] **Step 3: Update active documentation**

Document these exact rules:

- Interactive Cursor first-run asks
  `Install global Atlassian MCP and start OAuth now?`, writes only the global
  entry after confirmation, streams OAuth, then health-checks.
- A current-repository project connector is reported as
  `Project MCP: PRESENT_IGNORED` and is never modified or accepted as global
  setup.
- Non-interactive Cursor first-run does not write global MCP configuration or
  start OAuth; it returns the interactive resume command.
- Existing compatible global connectors remain idempotent and unknown health
  remains fail-closed.

- [ ] **Step 4: Run documentation and release gates**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/release.sh
git diff --check
```

Expected: all commands exit `0`.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md handbook.md PACKAGE-DESIGN.md \
  tests/documentation-architecture.sh
git commit -m "docs: explain Cursor first-run MCP setup"
```

### Task 3: Verify and publish Issue #30 for review

**Files:**
- Update: GitHub Issue #30
- Create: pull request from `agent/issue-30-cursor-first-run-mcp`

**Interfaces:**
- Consumes: Tasks 1-2 and the approved design.
- Produces: one reviewable Issue #30 PR; no tag or release.

- [ ] **Step 1: Run complete verification**

Run:

```bash
sh -n bin/beroka-governance release/bootstrap.sh.in
for test_script in tests/*.sh; do sh "$test_script"; done
default_branch=$(gh repo view --json defaultBranchRef \
  --jq '.defaultBranchRef.name')
git diff --check "origin/$default_branch"...HEAD
test -z "$(git status --porcelain)"
```

Expected: every command exits `0`.

- [ ] **Step 2: Request independent review**

Review the exact `origin/main...HEAD` range. Fix every Critical or Important
finding, rerun the complete verification command, and record the reviewed full
commit SHA.

- [ ] **Step 3: Push after a fresh GitHub preflight**

Run:

```bash
beroka-governance preflight "$PWD" \
  --client codex --operation github-write --non-interactive
git push -u origin agent/issue-30-cursor-first-run-mcp
```

- [ ] **Step 4: Open and read back a draft PR**

Resolve `defaultBranchRef.name` immediately before PR creation. Open a draft PR
with `Fixes #30`, the approved first-run flow, full-suite evidence, and:

```text
Not run: merge, tag, and v1.0.4 release.
```

Read back base, head, draft state, exact head SHA, changed files, mergeability,
and status checks. Comment on Issue #30 with the PR link and evidence.

- [ ] **Step 5: Stop before merge or release**

Report the exact PR and reviewed head. Do not merge, tag, or release without a
new exact human confirmation, and do not start release work until Issue #31 is
handled.
