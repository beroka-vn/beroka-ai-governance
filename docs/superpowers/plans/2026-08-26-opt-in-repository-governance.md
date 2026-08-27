# Opt-In Repository Governance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate Beroka governance only for repositories with an exact record in the pinned Central catalog.

**Architecture:** Keep canonical remote and catalog resolution in `bin/beroka-governance` as the single activation boundary. Missing records become `NOT_GOVERNED`; context, preflight, and Cursor hooks return before loading or enforcing policy, while registered and malformed-record paths keep their current behavior.

**Tech Stack:** POSIX shell, Git, jq, awk, existing repository shell test harnesses.

**Spec:** `docs/superpowers/specs/2026-08-26-opt-in-repository-governance-design.md`

## Global Constraints

- Exact active-release catalog membership is the only activation signal.
- An unregistered context prints exactly `Result: NOT_GOVERNED` and `Repository: owner/repository`.
- Unregistered context is at most 160 bytes and eight words.
- Each managed entrypoint is at most 1,024 bytes and 140 words.
- Missing catalog records pass through; existing malformed records fail closed.
- No application repository files, new framework, or new dependency.
- Registered standalone, Backend, Frontend, integration, routing, role, OAuth, connector, and handoff behavior remains unchanged.

---

### Task 1: Central Repository Classification and CLI Results

**Files:**
- Modify: `tests/smoke.sh`
- Modify: `tests/routing.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: `canonical_repo`, `resolve_canonical_remote`, `normalize_github_url`, `catalog_record_for_slug`, and `parse_routing`.
- Produces: `ROUTING_STATE=NOT_GOVERNED`, `repository_is_governed`, and `print_not_governed`; later hook work consumes all three.

- [ ] **Step 1: Write failing context and preflight tests**

Replace the unknown-repository assertions in `tests/smoke.sh` with literal behavior checks:

```sh
unknown_output=$($CLI context "$unknown_repo")
[ "$unknown_output" = "$(printf '%s\n%s' \
  'Result: NOT_GOVERNED' \
  'Repository: beroka-vn/unknown')" ] ||
  fail 'unknown repository received governance context'
[ "$(printf '%s' "$unknown_output" | wc -c)" -le 160 ] ||
  fail 'unknown context exceeded 160 bytes'
[ "$(printf '%s' "$unknown_output" | wc -w)" -le 8 ] ||
  fail 'unknown context exceeded eight words'

: >"$CALLS"
unknown_preflight=$(
  PATH=$fake_bin:$PATH $CLI preflight "$unknown_repo" \
    --client codex --operation jira-write --non-interactive
)
assert_contains "$unknown_preflight" 'Result: NOT_GOVERNED'
[ ! -s "$CALLS" ] || fail 'unknown preflight invoked a connector or client'
```

Change the unknown fixture in `tests/routing.sh` to assert the same two-line result and absence of `# General Repository Governance`, `Profile:`, and `Routing:`. Keep registered clone/worktree assertions unchanged.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
sh tests/smoke.sh
sh tests/routing.sh
```

Expected: `tests/smoke.sh` fails because unknown context still includes source-only general and standalone rules; `tests/routing.sh` fails on the new compact-result assertion.

- [ ] **Step 3: Implement the shared state and compact result**

In `resolve_repository_context`, replace the synthetic standalone fallback with:

```sh
  else
    clear_routing_values
    ROUTING_STATE=NOT_GOVERNED
    return 0
  fi
  require_role_scope
```

Add these helpers near `cmd_context`:

```sh
repository_is_governed() {
  [ "$ROUTING_STATE" = ROUTING_ACTIVE ]
}

print_not_governed() {
  printf '%s\n' \
    'Result: NOT_GOVERNED' \
    "Repository: $REPOSITORY_SLUG"
}
```

After repository resolution in `cmd_context`, return through
`print_not_governed` before reading any runtime file. After repository
resolution in `cmd_preflight`, do the same before `require_enrolled_client`,
instruction verification, role, connector, or operation checks.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
sh tests/smoke.sh
sh tests/routing.sh
```

Expected: both scripts print their PASS result and make no client call for the unregistered preflight.

- [ ] **Step 5: Commit**

```bash
git add bin/beroka-governance tests/smoke.sh tests/routing.sh
git commit -m "feat: make repository governance opt in"
```

### Task 2: Cursor Hook Pass-Through

**Files:**
- Modify: `tests/cursor-hooks.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: `ROUTING_STATE`, `repository_is_governed`, canonical workspace roots, and the current strict `cursor_resolve_workspaces` path.
- Produces: `CURSOR_GOVERNANCE_STATE=NOT_GOVERNED|ROUTING_ACTIVE` and early hook outcomes.

- [ ] **Step 1: Write failing unregistered hook tests**

Using the existing `other_repo` fixture, construct single-root requests for all five events. Assert exact pass-through behavior:

```sh
unknown_base=$(jq -nc --arg root "$other_repo" \
  '{conversation_id:"unknown",generation_id:"unknown",workspace_roots:[$root]}')

unknown_start=$(hook sessionStart "$unknown_base")
assert_contains "$unknown_start" 'Result: NOT_GOVERNED'
assert_not_contains "$unknown_start" '# General Repository Governance'

assert_contains "$(hook beforeSubmitPrompt "$(printf '%s\n' "$unknown_base" |
  jq -c '.prompt="create a Jira issue"')")" '{}'
assert_contains "$(hook preCompact "$unknown_base")" '{}'

unknown_mcp=$(printf '%s\n' "$unknown_base" | jq -c '. + {
  tool_name:"jira.create_issue",
  url:"https://example.atlassian.net",
  tool_input:{description:"not governed"}
}')
assert_contains "$(hook beforeMCPExecution "$unknown_mcp")" '"permission":"allow"'

unknown_shell=$(printf '%s\n' "$unknown_base" |
  jq -c '.command="gh issue create --title test"')
assert_contains "$(hook beforeShellExecution "$unknown_shell")" '"permission":"allow"'
```

Add a two-unknown-root fixture and assert the same MCP pass-through. Add a
registered-plus-unknown multi-root fixture and assert
`GOVERNANCE_CONTEXT_REQUIRED`, proving an unknown root cannot disable a
registered one. Clear the fake client call log before the unknown cases and
assert it remains empty.

- [ ] **Step 2: Run the Cursor test and verify RED**

Run:

```bash
sh tests/cursor-hooks.sh
```

Expected: the unknown session receives full standalone context or a governed hook denial instead of pass-through.

- [ ] **Step 3: Implement workspace activation probing**

Add a small classifier that resolves every distinct valid Git root in a
subshell and counts cataloged roots without running role checks for missing
records:

```sh
cursor_classify_governance() {
  CURSOR_GOVERNANCE_STATE=NOT_GOVERNED
  while IFS= read -r ccg_top; do
    [ -n "$ccg_top" ] || continue
    ccg_state=$(cursor_probe_workspace_profile "$ccg_top" | awk -F '\t' '{print $3}') || return 1
    [ "$ccg_state" != ROUTING_ACTIVE ] || {
      CURSOR_GOVERNANCE_STATE=ROUTING_ACTIVE
      return 0
    }
  done <<EOF
$CURSOR_WORKSPACES
EOF
}
```

Refactor root collection so it runs before strict single/FULL_STACK selection.
If no root is registered, retain one root only for repository identity output
and return the `NOT_GOVERNED` classification. If any root is registered, call
the current strict resolver unchanged.

At the start of each hook, after JSON/root parsing and classification:

- `sessionStart`: return compact additional context without writing a receipt;
- `beforeSubmitPrompt` and `preCompact`: print `{}`;
- `beforeMCPExecution` and `beforeShellExecution`: call `cursor_allow`.

Do not call provider parsing, receipt matching, template checks, preflight, or
client commands after the early return.

- [ ] **Step 4: Run Cursor and routing tests and verify GREEN**

Run:

```bash
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: both scripts pass; mixed registered/unknown remains fail-closed and all registered fixtures retain their prior outcomes.

- [ ] **Step 5: Commit**

```bash
git add bin/beroka-governance tests/cursor-hooks.sh
git commit -m "fix: pass through hooks outside governed repos"
```

### Task 3: Minimal Cross-Client Entrypoints and Registration Guidance

**Files:**
- Modify: `templates/agent-entrypoints/AGENTS.md`
- Modify: `templates/agent-entrypoints/CLAUDE.md`
- Modify: `templates/agent-entrypoints/CURSOR-USER-RULE.txt`
- Modify: `runtime/entrypoint.md`
- Modify: `README.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `handbook.md`
- Modify: `tests/bootstrap.sh`
- Modify: `tests/documentation-architecture.sh`
- Modify: `tests/release.sh`

**Interfaces:**
- Consumes: managed block markers, bootstrap personal-text preservation, and the two-line context contract.
- Produces: the same minimal sentinel contract for Codex, Claude, and Cursor.

- [ ] **Step 1: Write failing size and content assertions**

In `tests/documentation-architecture.sh`, for each managed entrypoint assert:

```sh
[ "$(wc -c <"$file" | tr -d ' ')" -le 1024 ] ||
  fail "$file exceeds the 1024-byte sentinel ceiling"
[ "$(wc -w <"$file" | tr -d ' ')" -le 140 ] ||
  fail "$file exceeds the 140-word sentinel ceiling"
require_text "$file" 'Result: NOT_GOVERNED'
require_text "$file" 'beroka-governance context "$PWD"'
reject_text "$file" 'createJiraIssue'
reject_text "$file" 'confluence-handoff-write'
reject_text "$file" 'mcp login atlassian'
```

Update `tests/bootstrap.sh` to compare installed managed blocks with the new
minimal templates while preserving personal text. Remove assertions that
require the global entrypoints to carry client-specific OAuth policy. Update
`tests/release.sh` expectations from source-only fallback to opt-in wording.

- [ ] **Step 2: Run documentation and bootstrap tests and verify RED**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/bootstrap.sh
sh tests/release.sh
```

Expected: size and forbidden-policy assertions fail against the current 3.8 KB entrypoints.

- [ ] **Step 3: Replace global blocks with the minimal sentinel**

Use the same body in all three client templates, retaining Codex/Claude managed
markers:

```markdown
## Beroka AI Governance

In a Git repository, before Jira, GitHub, Confluence, planning, or
implementation work, run `beroka-governance context "$PWD"`. Apply Beroka
governance only when it does not return `Result: NOT_GOVERNED`.

Rerun after session resume or context compaction, when the current Git
repository or workspace changes, when another repository enters scope, or when
a plan becomes shared/full-stack. Run it for every exact target repository.
```

Update `runtime/entrypoint.md` to state that exact catalog membership has
already activated governance and remove the source-only fallback. Add concise
README, package-design, and handbook registration text: catalog record,
reviewed PR, immutable release, then user-scoped upgrade. State explicitly that
the retired local `register` command and application-repository mutation are
not registration paths.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/bootstrap.sh
sh tests/release.sh
```

Expected: all three scripts pass, installed personal text is preserved, and each managed entrypoint stays below both ceilings.

- [ ] **Step 5: Commit**

```bash
git add templates/agent-entrypoints runtime/entrypoint.md README.md \
  PACKAGE-DESIGN.md handbook.md tests/bootstrap.sh \
  tests/documentation-architecture.sh tests/release.sh
git commit -m "docs: reduce global governance to a sentinel"
```

### Task 4: Full Regression and Release Validation

**Files:**
- Modify only files required to correct a failure caused by Tasks 1-3.

**Interfaces:**
- Consumes: complete branch implementation.
- Produces: release-ready validation evidence.

- [ ] **Step 1: Run syntax checks**

Run:

```bash
sh -n bin/beroka-governance release/bootstrap.sh.in tests/*.sh
```

Expected: exit 0 with no output.

- [ ] **Step 2: Run all eight repository test groups**

Run:

```bash
for test_file in tests/bootstrap.sh tests/connectors.sh tests/cursor-hooks.sh \
  tests/documentation-architecture.sh tests/launcher.sh tests/release.sh \
  tests/routing.sh tests/smoke.sh; do
  sh "$test_file" || exit 1
done
```

Expected: every group prints its PASS result and exits 0.

- [ ] **Step 3: Inspect the stacked diff**

Run:

```bash
git diff --check 36a2c28912b9d0d3acd410a631935dbe8e849645..HEAD
git status --short --branch
git diff --stat 36a2c28912b9d0d3acd410a631935dbe8e849645..HEAD
```

Expected: no whitespace errors, a clean worktree, and changes limited to issue #83 artifacts, runtime, entrypoints, docs, and regression tests.
