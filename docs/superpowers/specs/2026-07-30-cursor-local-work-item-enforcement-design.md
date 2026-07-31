# Cursor Local Work-Item Enforcement Design

**Date:** 2026-07-30
**Issue:** [GitHub #31](https://github.com/beroka-vn/beroka-ai-governance/issues/31)
**Status:** Approved for implementation
**Target release:** `v1.0.4`

## Goal

Prevent a local Cursor agent from creating or updating Jira and GitHub work
items until the active Beroka governance release has supplied fresh repository
context, the matching write preflight has passed, and the outgoing work item
uses the governed structure and language.

The incident boundary is runtime enforcement. The existing Cursor User Rule
remains useful guidance, but its `Instruction: USER_CONFIRMED` acknowledgement
must not be reported as proof that writes are blocked.

## Language Boundary

AI-generated Jira and GitHub work items, comments, pull-request descriptions,
and other technical artifacts default to English. Chat may follow the user's
language and must not determine artifact language.

A user may request another artifact language in the current Cursor prompt with
this canonical directive:

```text
Work-item language: <language>
```

The hook stores only the normalized language identifier for that generation.
It does not persist the prompt or infer an override from conversational text.
Without a valid directive, English remains authoritative.

## Selected Boundary

Use Cursor's documented local user hooks in `~/.cursor/hooks.json`. User hooks
apply across local workspaces, receive conversation, generation, and workspace
metadata on standard input, and may block MCP or shell execution. Security
hooks use `failClosed: true`.

Bootstrap idempotently adds one managed command to each required event while
preserving unrelated user hooks:

- `sessionStart` loads governance context for exactly one Git workspace and
  creates a short-lived receipt.
- `beforeSubmitPrompt` records the current generation's canonical language
  directive, defaulting to English.
- `preCompact` invalidates the conversation receipt.
- `beforeMCPExecution` guards Jira and GitHub work-item creates and updates.
- `beforeShellExecution` blocks known direct `gh` issue and pull-request write
  commands that bypass the governed MCP path.

The managed command calls the already installed
`~/.local/bin/beroka-governance cursor-hook <event>`. No daemon, proxy, new
dependency, or Cursor database edit is required.

References:

- [Cursor hooks](https://cursor.com/docs/hooks)
- [Cursor hooks partner announcement](https://cursor.com/blog/hooks-partners)

## Receipt Model

Receipts live below
`$XDG_STATE_HOME/beroka-ai-governance/cursor/`, falling back to
`~/.local/state/beroka-ai-governance/cursor/`, with user-only permissions.
They contain only:

- conversation and generation identifiers;
- the normalized workspace path and canonical repository slug;
- the verified active governance version and commit;
- context status and creation time; and
- the normalized work-item language.

A receipt is valid only for the same conversation, generation, workspace,
repository, active release, and hook process. `preCompact`, workspace changes,
missing or multiple Git workspaces, malformed input, and release changes
invalidate it. The hook never stores credentials, tokens, prompts, or work-item
content.

## Write Guard

`beforeMCPExecution` classifies known Jira and GitHub issue, pull-request, and
comment create/update operations using Cursor's tool name, provider URL or
command, and tool input. A write-like operation against those providers that
cannot be classified is denied rather than guessed.

Immediately before an allowed external write, the hook runs the existing
repository-specific preflight with the selected Cursor client:

```bash
beroka-governance preflight REPO --client cursor --operation jira-write
beroka-governance preflight REPO --client cursor --operation github-write
```

The write is allowed only when preflight returns `Result: PASS` and its payload
contains the governed work-item fields. GitHub items must include the required
native type or fallback type label, one `area:*`, one `priority:*`, owner, and
primary Jira linkage where applicable. Jira items must include the resolved
project, type, parent or approved standalone reason, assignee, priority, and
GitHub linkage where applicable.

The payload language must match the current generation's directive. English is
the default. The deterministic check rejects an explicit non-English template
marker without a matching override and requires the canonical language field;
it does not claim natural-language detection.

Denied operations return a stable result and actionable remediation:

- `GOVERNANCE_CONTEXT_REQUIRED`
- `WORK_ITEM_TEMPLATE_REQUIRED`
- `WORK_ITEM_LANGUAGE_REQUIRED`
- the existing `LABEL_CONFIGURATION_REQUIRED`
- the unchanged preflight result when preflight itself fails

`beforeShellExecution` denies common direct GitHub write commands including
`gh issue create`, `gh issue edit`, `gh pr create`, `gh pr edit`, and write
forms of `gh api` targeting issues, pulls, or comments. Its remediation routes
the agent through the governed MCP path.

## Bootstrap and Doctor

Cursor bootstrap:

1. validates or creates `~/.cursor/hooks.json`;
2. preserves unrelated top-level keys and hook entries;
3. adds missing managed entries exactly once;
4. refuses invalid JSON, symlinks, or a conflicting managed command; and
5. installs no project-local hook.

Doctor reports the three boundaries separately:

```text
Instruction: USER_CONFIRMED
Runtime hook: INSTALLED
Runtime enforcement: PASS
```

Runtime enforcement passes only after a local canary proves that an unprepared
write is denied. Missing, malformed, or fail-open security hooks make Doctor
fail closed; the instruction acknowledgement alone is insufficient.

## Security and Failure Behavior

- Hook input is untrusted JSON and is validated with the existing `jq`
  prerequisite.
- Security events set `failClosed: true`; malformed input and internal hook
  failures deny writes.
- The hook executes only the verified active release and existing preflight
  logic.
- Multi-root and non-Git workspaces do not guess a repository.
- Personal hooks are preserved and never executed by governance tests.
- Cursor Cloud agents are outside this change because the affected users run
  Cursor IDE locally.

The supported threat model is a normal local Cursor agent using configured MCP
tools or common `gh` commands. A malicious OS user, a modified Cursor binary,
or arbitrary raw HTTP scripts can bypass user-owned local hooks and are outside
scope. Covering those cases would require an organization-controlled network or
identity enforcement layer.

## Repository Changes

Keep the implementation within:

- `bin/beroka-governance` for hook dispatch, receipts, write classification,
  installation, and Doctor verification;
- one focused `tests/cursor-hooks.sh` regression script plus existing bootstrap,
  connector, documentation, and release assertions where needed;
- `templates/agent-entrypoints/CURSOR-USER-RULE.txt` and
  `runtime/rules/work-items.md` for the language and governed-path contract; and
- `README.md`, `handbook.md`, `governance.md`, `workflow.md`, and
  `PACKAGE-DESIGN.md` only where current Cursor claims require correction.

Do not add a proxy, daemon, language-detection dependency, project hook,
organization policy service, or speculative client abstraction.

## Validation

Temporary HOME, XDG, repository, and fake preflight fixtures must prove:

- bootstrap merges hooks without deleting personal entries and is idempotent;
- invalid or conflicting hook configuration fails without overwriting it;
- `sessionStart` creates a receipt only for one recognized Git workspace;
- compaction, workspace, generation, and active-release changes invalidate it;
- default English and an explicit current-generation override are isolated;
- unprepared, untemplated, mislabeled, or wrong-language MCP writes are denied;
- matching Jira and GitHub writes call a fresh operation preflight and may pass;
- known direct `gh` writes are denied while read-only shell commands pass;
- malformed security-hook input fails closed;
- Doctor distinguishes instruction acknowledgement from installed and passing
  runtime enforcement; and
- the complete shell test suite remains green.

## Release Boundary

Issue #31 lands through its own branch and pull request. `v1.0.4` may be tagged
and published only after the required issue pull requests are merged and the
human confirms the exact reviewed pull requests and commits. Existing release
tags remain immutable.
