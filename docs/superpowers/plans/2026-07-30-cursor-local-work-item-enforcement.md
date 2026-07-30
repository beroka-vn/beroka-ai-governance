# Cursor Local Work-Item Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make local Cursor Jira and GitHub work-item writes fail closed until repository context, operation preflight, governed fields, and artifact language are valid.

**Architecture:** Add one `cursor-hook` dispatch surface to the existing POSIX-shell CLI and install it as five documented user-level Cursor hook events. Keep short-lived receipts in user state, reuse existing context and preflight functions, and validate the outgoing MCP or shell request at the hook boundary without a proxy, daemon, or new dependency.

**Tech Stack:** POSIX shell, `jq`, Cursor user hooks JSON, existing shell test harness, Git.

## Global Constraints

- Target release is exactly `v1.0.4`; existing release tags remain immutable.
- Local Cursor user hooks live in `~/.cursor/hooks.json`; do not install project hooks.
- Preserve unrelated top-level JSON keys and personal hook entries.
- Set `failClosed: true` on `beforeMCPExecution` and `beforeShellExecution`.
- AI-generated work items and technical artifacts default to English.
- A non-English override is valid only from `Work-item language: <language>` in the current generation.
- Do not persist prompts, work-item content, credentials, or tokens.
- Reuse `cmd_context`, `cmd_preflight`, routing state, and the installed `jq`; add no proxy, daemon, language detector, dependency, or speculative client abstraction.
- Fail closed for malformed hook input, multiple workspaces, stale receipts, unclassified Jira/GitHub write tools, invalid templates, and preflight failures.
- Cover normal configured MCP tools and common `gh` writes; arbitrary raw HTTP scripts and malicious local users are outside scope.
- Bootstrap and Doctor must distinguish `Instruction: USER_CONFIRMED`, `Runtime hook: INSTALLED`, and `Runtime enforcement: PASS`.
- Do not merge, tag, or publish from an implementation task.

---

### Task 1: Cursor hook runtime and fail-closed receipts

**Files:**
- Create: `tests/cursor-hooks.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: existing `load_active_release`, `resolve_repository_context`, `cmd_context`, `cmd_preflight`, `die`, and `pass_result`.
- Produces: CLI command `cursor-hook EVENT`; state files below `${XDG_STATE_HOME:-$HOME/.local/state}/beroka-ai-governance/cursor`; JSON hook responses on stdout.

- [ ] **Step 1: Add the focused test harness and RED cases**

Create `tests/cursor-hooks.sh` with the same `set -eu`, temporary HOME/XDG,
`fail`, `assert_contains`, and temporary Git repository patterns used by
`tests/smoke.sh`. Build a minimal verified fake active release containing the
current runtime and catalog, then invoke the source CLI directly.

Send base hook input in this shape:

```json
{
  "conversation_id": "conversation-1",
  "generation_id": "generation-1",
  "workspace_roots": ["/tmp/known-repository"]
}
```

Add assertions for these exact cases:

1. `cursor-hook sessionStart` with one recognized Git workspace returns JSON
   containing `.additional_context`, the repository slug, governance version,
   and `Routing: ROUTING_ACTIVE`.
2. `cursor-hook beforeSubmitPrompt` with prompt
   `"Work-item language: Vietnamese"` records `vi`; a subsequent generation
   without the directive records `en`.
3. `cursor-hook preCompact` removes the receipt so the next guarded write
   returns `GOVERNANCE_CONTEXT_REQUIRED`.
4. malformed JSON, a non-Git workspace, and two workspace roots fail closed.
5. `beforeMCPExecution` denies a GitHub or Jira write when the receipt,
   generation, workspace, active release, or governed fields do not match.
6. an unknown write-like tool whose provider URL contains `github.com` or
   `atlassian.net` is denied.
7. `beforeShellExecution` denies `gh issue create`, `gh issue edit`,
   `gh pr create`, `gh pr edit`, and write `gh api` calls to issues, pulls, or
   comments, while allowing `gh issue view` and `git status`.

Run:

```bash
sh tests/cursor-hooks.sh
```

Expected: FAIL because `cursor-hook` is not a recognized command.

- [ ] **Step 2: Add state and JSON helpers**

At the top of `bin/beroka-governance`, derive:

```sh
STATE_ROOT=${XDG_STATE_HOME:-$HOME/.local/state}/beroka-ai-governance
CURSOR_STATE_ROOT=$STATE_ROOT/cursor
```

Add minimal helpers which:

- require `jq`;
- validate one JSON object from stdin;
- accept only non-empty scalar `conversation_id` and `generation_id`;
- accept exactly one string in `workspace_roots`;
- canonicalize the workspace with `git -C "$workspace" rev-parse
  --show-toplevel`;
- create `CURSOR_STATE_ROOT` with mode `700`;
- derive a safe receipt filename from SHA-256 of `conversation_id`;
- write receipts atomically with mode `600`; and
- compare workspace, repository slug, generation, active version, and active
  commit before a guarded write.

Use existing `sha256_file`/Git hashing support if present. Do not use a raw
conversation identifier as a pathname.

- [ ] **Step 3: Implement session, prompt, and compaction events**

Add `cmd_cursor_hook EVENT` and dispatch it from `main`.

For `sessionStart`:

1. validate input and resolve the one Git workspace;
2. call the existing active-release and repository-context functions;
3. capture the same governed text exposed by `cmd_context`;
4. write a receipt with default language `en`; and
5. emit:

```json
{
  "env": {
    "BEROKA_GOVERNANCE_CONTEXT": "PASS"
  },
  "additional_context": "<context output>"
}
```

For `beforeSubmitPrompt`, parse only a complete line matching the
case-insensitive canonical directive. Normalize `English` to `en`,
`Vietnamese` to `vi`, and otherwise use a lower-case ASCII language identifier
matching `[a-z][a-z0-9-]{1,31}`. Invalid directives return
`WORK_ITEM_LANGUAGE_REQUIRED`. Without a directive, record `en` for that
generation. Do not store the prompt.

For `preCompact`, delete only the current conversation receipt and return `{}`.

- [ ] **Step 4: Implement MCP classification and validation**

Classify GitHub or Jira writes from `tool_name`, optional `url`/`command`, and
`tool_input`. Recognize create/update forms for issues, pull requests, and
comments. Treat provider-matched names containing `create`, `update`, `edit`,
`comment`, `issue`, or `pull` as writes; deny provider-matched write-like tools
that are not safely classified.

Require the serialized `tool_input` object to contain a canonical marker:

```text
Work-item language: English
```

or the current override language name/identifier, plus the applicable governed
fields. For GitHub creation, require owner/assignee, type or configured fallback
type, one `area:*`, one `priority:*`, and Jira linkage or explicit `N/A`. For
Jira creation, require project, issue type, assignee/owner, priority, parent or
standalone reason, and GitHub linkage or explicit `N/A`. Update/comment
operations require the language marker and non-empty body/content, but do not
invent creation-only fields.

Return denials with:

```json
{
  "permission": "deny",
  "user_message": "Result: WORK_ITEM_TEMPLATE_REQUIRED",
  "agent_message": "<specific remediation>"
}
```

Use `GOVERNANCE_CONTEXT_REQUIRED`,
`WORK_ITEM_TEMPLATE_REQUIRED`, `WORK_ITEM_LANGUAGE_REQUIRED`, or
`LABEL_CONFIGURATION_REQUIRED` as specified by the failed boundary.

After all local checks pass, run a fresh:

```sh
cmd_preflight "$workspace" \
  --client cursor --operation "$operation" --non-interactive
```

Capture its output. Return `permission: allow` only when it exits zero and
contains `Result: PASS`; otherwise deny and preserve the returned governance
result in `user_message`.

- [ ] **Step 5: Implement common shell-write blocking**

Read `.command` from the hook input. Deny the exact common write families:

```text
gh issue create
gh issue edit
gh pr create
gh pr edit
gh api ... issues ...
gh api ... pulls ...
gh api ... comments ...
```

Only `gh api` invocations using a write method (`-X/--method`
`POST|PUT|PATCH|DELETE`) are blocked. Read-only `gh` and non-GitHub commands
return `{ "permission": "allow" }`.

- [ ] **Step 6: Run focused checks and commit**

Run:

```bash
sh -n bin/beroka-governance
sh -n tests/cursor-hooks.sh
sh tests/cursor-hooks.sh
```

Expected: all PASS.

Commit:

```bash
git add bin/beroka-governance tests/cursor-hooks.sh
git commit -m "feat: enforce governed Cursor work-item writes"
```

---

### Task 2: Idempotent hook installation and Doctor canary

**Files:**
- Modify: `tests/bootstrap.sh`
- Modify: `tests/cursor-hooks.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: `cmd_cursor_hook`, existing Cursor acknowledgement install and verification, `BEROKA_GOV_BIN_DIR`, and `cmd_doctor`.
- Produces: managed entries in `~/.cursor/hooks.json`; functions `install_cursor_hooks` and `verify_cursor_hooks`; Doctor runtime lines.

- [ ] **Step 1: Add RED bootstrap and Doctor cases**

In the existing Cursor bootstrap fixture, pre-create:

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "command": "/tmp/personal-hook",
        "timeout": 5
      }
    ]
  },
  "personal": {
    "preserved": true
  }
}
```

Assert successful Cursor bootstrap:

- keeps `.personal.preserved` and `/tmp/personal-hook`;
- adds exactly one managed entry to `sessionStart`, `beforeSubmitPrompt`,
  `preCompact`, `beforeMCPExecution`, and `beforeShellExecution`;
- uses the installed absolute CLI path followed by `cursor-hook <event>`;
- sets `failClosed: true` only on the two security events;
- leaves identical file bytes on a repeat bootstrap; and
- prints `Runtime hook: INSTALLED`.

Add adjacent failures for a symlinked hooks file, invalid JSON, and an existing
entry with the managed command but conflicting `failClosed`. Assert the
original file bytes remain unchanged.

For Doctor, assert a correct installation prints:

```text
Instruction: USER_CONFIRMED
Runtime hook: INSTALLED
Runtime enforcement: PASS
Result: PASS
```

Removing a managed entry or changing `failClosed` must make Doctor fail. An
acknowledgement without hooks must not print runtime PASS.

Run:

```bash
sh tests/bootstrap.sh
```

Expected: FAIL because bootstrap does not install hooks and Doctor does not run
the runtime canary.

- [ ] **Step 2: Merge managed hooks atomically**

Implement `install_cursor_hooks` with `jq`:

1. reject a symlink or non-regular existing `~/.cursor/hooks.json`;
2. use `{}` only when the file is absent;
3. require one JSON object and require `.hooks` to be absent or an object;
4. calculate the absolute installed command from
   `BEROKA_GOV_BIN_DIR/beroka-governance`;
5. for each event, reject an existing exact managed command whose object
   conflicts with the required security setting;
6. append only a missing managed object; and
7. write a temporary sibling, set mode `600`, and rename it over the target.

Managed entries are:

```json
{"command":"<absolute-cli> cursor-hook sessionStart"}
{"command":"<absolute-cli> cursor-hook beforeSubmitPrompt"}
{"command":"<absolute-cli> cursor-hook preCompact"}
{"command":"<absolute-cli> cursor-hook beforeMCPExecution","failClosed":true}
{"command":"<absolute-cli> cursor-hook beforeShellExecution","failClosed":true}
```

Call the installer during successful Cursor enrollment after the verified CLI
is installed and before reporting bootstrap PASS.

- [ ] **Step 3: Verify configuration and run the Doctor canary**

Implement `verify_cursor_hooks` using the same expected command objects. It
passes only when every object appears exactly once and both security hooks
contain boolean `true`.

After configuration verification, Doctor sends malformed/unprepared JSON to:

```sh
"$BEROKA_GOV_BIN_DIR/beroka-governance" \
  cursor-hook beforeMCPExecution
```

The canary passes only when the command exits successfully with JSON
permission `deny` and a `GOVERNANCE_CONTEXT_REQUIRED` message. Print:

```text
Runtime hook: INSTALLED
Runtime enforcement: PASS
```

Do not replace or rename the existing instruction line.

- [ ] **Step 4: Run focused checks and commit**

Run:

```bash
sh -n bin/beroka-governance
sh tests/cursor-hooks.sh
sh tests/bootstrap.sh
sh tests/connectors.sh
```

Expected: all PASS.

Commit:

```bash
git add bin/beroka-governance tests/cursor-hooks.sh tests/bootstrap.sh
git commit -m "feat: install and verify Cursor security hooks"
```

---

### Task 3: Language policy, package contract, and release gates

**Files:**
- Modify: `templates/agent-entrypoints/CURSOR-USER-RULE.txt`
- Modify: `runtime/rules/work-items.md`
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `tests/documentation-architecture.sh`
- Modify: `tests/release.sh`
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: the hook command, canonical language directive, Doctor output, and
  threat model from Tasks 1 and 2.
- Produces: client guidance and release assertions that match runtime behavior.

- [ ] **Step 1: Add RED documentation and package assertions**

Add compact assertions which require:

- the Cursor User Rule to say technical artifacts default to English, chat
  language is not artifact language, and an override uses
  `Work-item language: <language>`;
- runtime work-item rules to apply the same default across clients;
- README/handbook to describe local user hooks and the three Doctor lines;
- package design to state that security hooks are fail closed and personal
  hooks are preserved;
- no document to claim `USER_CONFIRMED` is runtime verification; and
- `tests/cursor-hooks.sh` to be executable and included in the documented and
  release-gate test lists.

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/release.sh
```

Expected: FAIL on the new assertions before documents are updated.

- [ ] **Step 2: Update the authoritative policy and Cursor instruction**

Add this rule to `runtime/rules/work-items.md`:

```text
AI-generated Jira and GitHub work items and technical artifacts default to
English. Chat language does not select artifact language. Use another language
only when the user explicitly supplies `Work-item language: <language>` for
the current generation.
```

Add the same operating instruction to
`templates/agent-entrypoints/CURSOR-USER-RULE.txt`, including that governed
Jira/GitHub writes must use the configured MCP tools and never direct `gh`
write commands.

- [ ] **Step 3: Correct current runtime and package documentation**

Keep documentation short and consistent:

- README: state Cursor bootstrap installs documented global local hooks and
  show the three Doctor results.
- Handbook: replace the instruction-only limitation with the new runtime
  boundary and explain the canonical override.
- Governance/workflow: state the cross-client English default and fresh
  preflight requirement at the write boundary.
- Package design: document atomic JSON merge, personal-hook preservation,
  fail-closed security events, receipt location/data minimization, canary, and
  the explicit local-agent threat model.

Do not add a second setup command or a manual JSON-edit procedure.

- [ ] **Step 4: Run all release gates and commit**

Run:

```bash
sh -n bin/beroka-governance
sh tests/bootstrap.sh
sh tests/connectors.sh
sh tests/cursor-hooks.sh
sh tests/documentation-architecture.sh
sh tests/launcher.sh
sh tests/release.sh
sh tests/routing.sh
sh tests/smoke.sh
git diff --check
```

Expected: all PASS and no whitespace errors.

Commit:

```bash
git add templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  runtime/rules/work-items.md README.md handbook.md governance.md workflow.md \
  PACKAGE-DESIGN.md tests/documentation-architecture.sh tests/release.sh \
  tests/smoke.sh
git commit -m "docs: enforce English work-item artifacts"
```

---

### Task 4: Publish the implementation branch

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: clean branch, all passing release gates, exact Issue #31 scope.
- Produces: pushed branch, draft pull request linked to Issue #31, and issue
  evidence comment.

- [ ] **Step 1: Verify branch scope and evidence**

Run:

```bash
git status --short
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
```

Confirm only Issue #31 changes are present and record the exact HEAD commit.

- [ ] **Step 2: Push after a fresh GitHub-write preflight**

Run immediately before pushing:

```bash
beroka-governance preflight "$PWD" \
  --client codex --operation github-write --non-interactive
```

Require `Result: PASS`, then push
`agent/issue-31-cursor-hard-enforcement`.

- [ ] **Step 3: Open one draft pull request after another fresh preflight**

Use an English title and body:

```text
Title: Enforce governed work-item writes in local Cursor

Body:
Closes #31

## Summary
- install documented fail-closed local Cursor hooks
- require fresh context and write preflight before Jira/GitHub mutations
- default AI-generated technical artifacts to English unless explicitly overridden

## Validation
- list every passing release-gate command
```

Read back base `main`, head branch, draft state, changed files, exact head
commit, and check status. Do not merge.

- [ ] **Step 4: Comment on Issue #31 after a third fresh preflight**

Post the draft PR URL, exact head commit, and test evidence in English. Read
back the created comment. Do not close the issue, merge the PR, create a tag,
or publish a release.

