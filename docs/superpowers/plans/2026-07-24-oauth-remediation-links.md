# OAuth Remediation Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Return provider-owned OAuth remediation for Atlassian and GitHub only when the requested external operation needs authentication.

**Architecture:** Keep the existing client-specific Atlassian flow and fix its Codex response parsing. Add an early `github-write` branch to preflight that checks GitHub CLI auth without resolving Jira/Confluence routing; provider login processes remain attached directly to the terminal so Governance never captures their OAuth URLs or credentials.

**Tech Stack:** POSIX shell, Git, GitHub CLI, jq, isolated shell tests with temporary HOME/XDG directories.

## Global Constraints

- `--client codex|claude|cursor` selects exactly one client.
- Interactive OAuth requires confirmation and streams the provider command directly.
- Non-interactive mode never starts OAuth or a browser.
- Dynamic OAuth URLs, OAuth state, and credentials are never parsed, logged, or stored by Governance.
- GitHub auth is checked only for `github-write`; Atlassian auth is checked only for Jira/Confluence connector operations.
- No developer API token input is accepted.
- Do not move or overwrite the published `v1.0.0` tag.

---

### Task 1: Codex Atlassian Compatibility and URL Pass-through

**Files:**
- Modify: `tests/connectors.sh:84-165`
- Modify: `bin/beroka-governance:1050-1067`
- Modify: `bin/beroka-governance:1704-1732`
- Modify: `bin/beroka-governance:1908-1916`

**Interfaces:**
- Consumes: `codex mcp get atlassian --json` and `codex app-server --stdio`.
- Produces: `connector_state codex` accepting exactly one legacy `url` or current `transport.url`; `connector_health codex` returning `1` for OAuth with no tools.

- [ ] **Step 1: Add failing connector tests**

Extend the fake Codex endpoint cases:

```sh
transport-url)
  printf '%s\n' \
    '{"name":"atlassian","transport":{"type":"streamable_http","url":"https://mcp.atlassian.com/v1/mcp/authv2","bearer_token_env_var":null,"http_headers":null,"env_http_headers":null}}'
  ;;
duplicate-transport-url)
  printf '%s\n' \
    '{"name":"atlassian","transport":{"type":"streamable_http","url":"https://wrong.invalid/mcp","url":"https://mcp.atlassian.com/v1/mcp/authv2"}}'
  ;;
both-url-shapes)
  printf '%s\n' \
    '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2","transport":{"type":"streamable_http","url":"https://mcp.atlassian.com/v1/mcp/authv2"}}'
  ;;
```

Assert `transport-url` reaches `Authentication: PASS`, while
`duplicate-transport-url` and `both-url-shapes` return `CONNECTOR_MISSING`.
Change fake `mcp login atlassian` to print a sentinel URL before setting health:

```sh
printf '%s\n' \
  'OAuth URL: https://auth.example.test/authorize?state=one-time'
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-codex-health"
```

Assert the interactive command output contains that exact URL and that `rg`
cannot find `auth.example.test` under temporary HOME/XDG data/config paths.

- [ ] **Step 2: Run the connector test and verify RED**

Run:

```sh
sh tests/connectors.sh
```

Expected: failures report that the current Codex transport endpoint is rejected
and empty OAuth tools are not classified as `ATLASSIAN_AUTH_REQUIRED`.

- [ ] **Step 3: Accept exactly one supported Codex endpoint shape**

Replace the top-level-only stream predicate with path-count validation:

```sh
printf '%s\n' "$cs_output" |
  jq -e -s --stream --arg url "$ATLASSIAN_MCP_URL" '
    def values($path):
      [.[] | select(length == 2 and .[0] == $path) | .[1]];
    (values(["name"]) == ["atlassian"]) and
    (
      (values(["url"]) == [$url] and
       values(["transport", "url"]) == [] and
       values(["transport", "type"]) == []) or
      (values(["url"]) == [] and
       values(["transport", "url"]) == [$url] and
       values(["transport", "type"]) == ["streamable_http"])
    )
  ' >/dev/null 2>&1 && return 0
```

For Codex `oAuth`, change the empty-tool result from unknown to auth-required:

```sh
[ -n "$ch_tools" ] && return 0
return 1
```

Add `Provider: atlassian` to `auth_required` output without changing the result
code or remediation command.

- [ ] **Step 4: Run the connector test and verify GREEN**

Run:

```sh
sh tests/connectors.sh
```

Expected: `PASS: connector setup`.

- [ ] **Step 5: Commit Task 1**

```sh
git add bin/beroka-governance tests/connectors.sh
git commit -m "fix: surface Atlassian OAuth remediation"
```

### Task 2: Operation-scoped GitHub OAuth

**Files:**
- Modify: `tests/routing.sh:250-610`
- Modify: `bin/beroka-governance:1006-1048`
- Modify: `bin/beroka-governance:1908-2088`

**Interfaces:**
- Consumes: canonical `github.com` repository registration, selected client
  executable, `gh auth status --hostname github.com`, and
  `gh auth login --hostname github.com --web`.
- Produces: `github-write` preflight with `PASS`,
  `GITHUB_AUTH_REQUIRED`, or `GOVERNANCE_NOT_READY`.

- [ ] **Step 1: Add failing isolated GitHub tests**

Add a fake `gh` to `tests/routing.sh`:

```sh
cat >"$FAKE_BIN/gh" <<'EOF'
#!/bin/sh
set -eu
printf 'gh %s\n' "$*" >>"$CALLS"
case "$*" in
  'auth status --help'|'auth login --help') exit 0 ;;
  'auth status --hostname github.com')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-github-health" 2>/dev/null || :)" in
      healthy) exit 0 ;;
      unknown) printf '%s\n' 'network unavailable' >&2; exit 1 ;;
      *) printf '%s\n' 'You are not logged into any GitHub hosts.' >&2; exit 1 ;;
    esac
    ;;
  'auth login --hostname github.com --web')
    printf '%s\n' 'OAuth URL: https://github.com/login/device'
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-github-health"
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$FAKE_BIN/gh"
```

Before publishing routing, assert:

```sh
if output=$($CLI preflight "$consumer" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'non-interactive GitHub preflight accepted missing auth'
fi
assert_contains "$output" 'Provider: github'
assert_contains "$output" 'Result: GITHUB_AUTH_REQUIRED'
assert_contains "$output" \
  'Remediation: gh auth login --hostname github.com --web'
assert_not_contains "$(cat "$CALLS")" \
  'gh auth login --hostname github.com --web'
```

Run the interactive form through `script`, answer `y`, and assert the exact
fake OAuth URL is present, login is called once, health is rechecked, and the
result is `PASS`. Run again with healthy state and assert login is not called.
Set `unknown` health and assert `GOVERNANCE_NOT_READY`. Repeat once while local
routing differs from the default branch to prove `github-write` does not return
`ROUTING_CHANGE_PENDING`. Assert Jira preflight never calls `gh`.

- [ ] **Step 2: Run the routing test and verify RED**

Run:

```sh
sh tests/routing.sh
```

Expected: `github-write` is rejected as an unknown operation or blocked by
`ROUTING_REQUIRED`.

- [ ] **Step 3: Implement the minimal GitHub auth branch**

Add:

```sh
github_oauth_command() {
  printf '%s\n' 'gh auth login --hostname github.com --web'
}

github_auth_health() {
  gah_output=$(gh auth status --hostname github.com 2>&1) && return 0
  printf '%s\n' "$gah_output" | awk '
    {
      line=tolower($0)
      if (line ~ /not logged into any github hosts/ ||
          line ~ /failed to log in/ ||
          line ~ /token.*(invalid|expired|revoked)/) required=1
    }
    END { exit !required }
  ' && return 1
  return 2
}

github_auth_required() {
  gar_client=$1
  printf '%s\n' \
    "Client: $gar_client" \
    'Provider: github' \
    'Authentication: AUTH_REQUIRED' \
    "Remediation: $(github_oauth_command)"
  die GITHUB_AUTH_REQUIRED
}
```

Add the operation-specific dependency and preflight functions:

```sh
require_github_client() {
  rgc_client=$1
  rgc_executable=$(client_executable "$rgc_client")
  command -v "$rgc_executable" >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING "Missing dependency: $rgc_executable"
  command -v gh >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING 'Missing dependency: gh'
  gh auth status --help >/dev/null 2>&1 &&
    gh auth login --help >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING 'GitHub CLI lacks required auth commands'
}

github_preflight() {
  gp_client=$1 gp_non_interactive=$2
  require_github_client "$gp_client"
  gp_health=0
  github_auth_health || gp_health=$?
  case "$gp_health" in
    0) ;;
    1)
      gp_interactive=0
      if [ "$gp_non_interactive" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
        gp_interactive=1
      fi
      [ "$gp_interactive" -eq 1 ] ||
        github_auth_required "$gp_client"
      printf '%s\n' \
        "Client: $gp_client" \
        'Provider: github' \
        'Authentication: AUTH_REQUIRED'
      printf 'Start OAuth now? [y/N] '
      IFS= read -r gp_answer || gp_answer=
      case "$gp_answer" in
        y|Y|yes|YES)
          gh auth login --hostname github.com --web ||
            github_auth_required "$gp_client"
          gp_health=0
          github_auth_health || gp_health=$?
          case "$gp_health" in
            0) ;;
            1) github_auth_required "$gp_client" ;;
            *) die GOVERNANCE_NOT_READY \
                 'Cannot verify GitHub authentication health' ;;
          esac
          ;;
        *) github_auth_required "$gp_client" ;;
      esac
      ;;
    *) die GOVERNANCE_NOT_READY \
         'Cannot verify GitHub authentication health' ;;
  esac
  printf '%s\n' \
    "Client: $gp_client" \
    'Provider: github' \
    'Operation: github-write' \
    'Authentication: PASS' \
    'Result: PASS'
}
```

Immediately after `verify_registration "$pf_repo"` in `cmd_preflight`, branch:

```sh
if [ "$pf_operation" = github-write ]; then
  github_preflight "$pf_client" "$pf_non_interactive"
  return
fi
```

This placement intentionally bypasses routing resolution and all Atlassian
connector/capability checks.

- [ ] **Step 4: Run the routing and connector tests**

Run:

```sh
sh tests/routing.sh
sh tests/connectors.sh
```

Expected:

```text
PASS: routing state
PASS: connector setup
```

- [ ] **Step 5: Commit Task 2**

```sh
git add bin/beroka-governance tests/routing.sh
git commit -m "feat: add GitHub OAuth preflight"
```

### Task 3: User Contract and Full Verification

**Files:**
- Modify: `README.md:29-43`
- Modify: `handbook.md:90-110`
- Modify: `handbook.md:430-447`
- Modify: `PACKAGE-DESIGN.md:170-190`
- Modify: `PACKAGE-DESIGN.md:300-325`

**Interfaces:**
- Consumes: the CLI behavior delivered by Tasks 1 and 2.
- Produces: documented interactive/non-interactive OAuth contract and result
  codes for users and future release maintainers.

- [ ] **Step 1: Add documentation assertions**

At the end of `tests/connectors.sh`, require the user docs to contain:

```sh
grep -F 'GITHUB_AUTH_REQUIRED' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fail 'package design does not document GitHub authentication result'
grep -F 'gh auth login --hostname github.com --web' "$ROOT/handbook.md" \
  >/dev/null ||
  fail 'handbook does not document GitHub OAuth remediation'
grep -F 'provider OAuth output directly' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document OAuth URL pass-through'
```

- [ ] **Step 2: Run the connector test and verify RED**

Run:

```sh
sh tests/connectors.sh
```

Expected: failure names the first missing OAuth contract sentence.

- [ ] **Step 3: Update the three user-facing documents**

Document:

```text
Interactive mode asks before login and streams provider OAuth output directly,
including the exact one-time URL or device URL/code. Governance does not parse,
log, or store that output.

Non-interactive mode never creates an OAuth session or opens a browser. It
returns ATLASSIAN_AUTH_REQUIRED or GITHUB_AUTH_REQUIRED and prints the exact
interactive remediation command.
```

Add `github-write` examples and state that it does not require repository
routing. Keep the existing client-specific Atlassian commands intact.

- [ ] **Step 4: Run all isolated tests and static checks**

Run:

```sh
sh -n bin/beroka-governance
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/routing.sh
git diff --check
git status --short
```

Expected: all three test scripts print `PASS`, shell parsing succeeds,
`git diff --check` is silent, and status contains only the intended
documentation/test/CLI changes.

- [ ] **Step 5: Verify tag immutability and no credential artifacts**

Run:

```sh
test "$(git rev-parse v1.0.0^{tag})" = \
  1f2db6bd75cf9d9a68d501c351fb2455448e04e1
! rg -n '(ghp_|github_pat_|access_token|refresh_token)' \
  bin tests README.md handbook.md PACKAGE-DESIGN.md
```

Expected: both commands exit `0`; no token or credential value is present.

- [ ] **Step 6: Commit Task 3**

```sh
git add README.md handbook.md PACKAGE-DESIGN.md tests/connectors.sh
git commit -m "docs: explain OAuth URL remediation"
```

- [ ] **Step 7: Final branch verification**

Run:

```sh
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: a clean branch containing the design commit and three implementation
commits, with no tag mutation.
