# Development Team and AI Agent Collaboration Workflow

This documentation standardizes how a team of 7–8 developers collaborates with
AI agents to receive work, implement it, review it, and trace results from Jira
to Confluence.

## Quick start

From the Git root of the repository to register, install the latest stable
release and set up one explicit client with:

```bash
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive
```

Replace `codex` with `claude` or `cursor`. The client flag is mandatory.
Run setup once for one client on each execution environment, then repeat it
for every additional client there. All enabled clients load the same pinned
governance release. Changing a model inside the same client needs no setup.

The command never opens a browser. When client-owned OAuth is missing or
invalid, installation and repository registration remain in place and the
command returns the exact remediation. Complete that client OAuth flow, then
rerun the same command. Governance never accepts or stores a developer API
token.

The launcher verifies its embedded annotated tag and commit before it executes
package code. Bootstrap installs and pins that release, registers the current
repository, configures exactly one selected client, and runs Doctor. Review the
resulting application-repository diff in its normal pull request before
merging, then start a fresh agent session so the client loads the registered
entrypoint.

Review and commit the repository changes, merge them through the normal
application-repository pull request, then start a fresh AI session. Existing
registrations keep their lock; bootstrap never silently upgrades them.

Client setup is additive: each bootstrap adds only its selected client's
entrypoint and never rewrites entrypoints already enabled for another client.
For example, add Claude Code later in its execution environment with:

```bash
beroka-governance bootstrap "$(git rev-parse --show-toplevel)" \
  --client claude \
  --non-interactive
```

The reviewed repository state enables the client, but connector configuration
and OAuth remain local to each developer machine. A developer using another
machine may still need to complete that client's local OAuth flow.

In the fresh session, load the pinned context and run the operation-specific
gate immediately before an external write:

```bash
beroka-governance context "$repo"
beroka-governance doctor "$repo" --client codex
beroka-governance preflight "$repo" \
  --client codex \
  --operation jira-write
beroka-governance preflight "$repo" \
  --client codex \
  --operation github-write
```

Routing-dependent preflight may return `ROUTING_REQUIRED` until the repository
has an active reviewed routing baseline. Source-only work can continue.

Run connector setup only after the selected client and its MCP dependencies are
installed. The command configures exactly that client and, in interactive mode,
offers to start its OAuth flow. It never accepts an Atlassian developer API
token. Use `--non-interactive` in automation; missing authentication then
returns `ATLASSIAN_AUTH_REQUIRED` with client-specific remediation and does not
open a browser. For Claude Code that remediation is `claude`, followed in the
client by `/mcp -> atlassian -> Authenticate`.

To configure another client explicitly, run
`beroka-governance setup-connectors --client claude` (or `codex`/`cursor`).

Interactive login streams provider OAuth output directly, including the exact
one-time URL or device URL/code. Governance does not parse, log, or store that
output. `github-write` checks `gh auth status` only for GitHub push and
pull-request work. Healthy auth is reused; missing auth asks before running
`gh auth login --hostname github.com --web`. Non-interactive mode instead
returns `GITHUB_AUTH_REQUIRED` with that remediation command.

`context` may continue source-only work while repository routing is unverified.
Run `preflight` immediately before each routing-dependent external write; the
exact selected client owns OAuth. Repository routing comes only from a freshly
fetched default-branch baseline. Pending local routing can be committed,
pushed, and reviewed, but cannot route Jira, Confluence, or cross-repository
writes.

`github-write` verifies repository registration but does not use repository
routing or inspect Atlassian. It therefore remains available while routing is
missing or pending.

`cross-repo-write` currently returns `ROUTING_REQUIRED` before inspecting a
client. The central release does not yet contain a reviewed exact counterpart
and workflow mapping, and the CLI accepts no exact target for that operation.

Backend and Frontend repositories are both officially supported. Each bootstrap
invocation registers exactly one explicit repository; run it again in the other
repository when needed. Governance never scans for or automatically registers
every repository on a developer machine. GitHub authentication remains
separate in each client; verify the selected Atlassian connector with
client-aware Doctor before connector preflight.

- Manager/coordinator: read the [operating workflow](workflow.md), then use
  the [Jira and Confluence template](templates/jira-confluence.md) and
  [GitHub Issue template](templates/github-issue.md).
- Developer: read the [governance rules](governance.md), accept a GitHub Issue
  that meets the Definition of Ready, and use the
  [Pull Request template](templates/pull-request.md).
- AI agent: accept an assignment using the
  [AI Agent Assignment Template](templates/ai-agent-assignment.md).
- New team member: read the [end-to-end traceability example](examples/end-to-end-traceability.md).

An AI agent chooses one of two modes:

- `planning-only`: confirm the project and active Epic before returning a draft
  or creating a Jira item;
- `execution`: verify that the requesting developer is the Jira assignee before
  modifying source, while preserving branch ownership and handoff rules.

Planning does not authorize Jira item creation. Jira reassignment happens only
after explicit developer confirmation and a successful read-back before AI
implementation begins.

Jira creation is complete only when the item can be read back and matches the
correct board and backlog. If board filters, status mapping, or backlog
configuration hide a created item, report `CREATED_BUT_NOT_VISIBLE`; do not
create a duplicate just to make a check pass.

## Language policy

- Documentation developers or managers read directly or copy into their work is
  written in Vietnamese while retaining English technical terms for tools.
- Prompts and handoff contracts intended exclusively for AI agents are written
  in English for consistent use across Codex, Claude, Cursor, Gemini, Kimi, and
  equivalent tools.

## Source of truth

| System | Responsibility |
| --- | --- |
| Jira | High-level outcome, business context, priority, assignee, timeline, and overall status |
| GitHub Issue | Technical scope, acceptance criteria, dependencies, validation, and work ownership |
| Backend repository contract artifact | Current OpenAPI/JSON Schema/event schema or contract version consumed by Frontend |
| Git branch/commit | Change history for one GitHub Issue |
| GitHub Pull Request | Review, validation evidence, approval authorization, and merge history |
| Backend Capability Registry | Cross-Epic Capability ID, exact content ID, artifact/version/commit, scope/domain/transport, and owner |
| Confluence | Canonical capability guides, Epic Integration Hubs, FE Capability Indexes, completion documents, and decisions |

Do not copy complete content between systems. Each record links to the next
source of truth with a stable URL.

## Traceability model

```text
Shared business outcome
├── BB Epic/Task ── BE GitHub Issue ── BE PR ── contract artifact
├── BF Epic/Task ── FE GitHub Issue ── FE PR
├── Backend Capability Registry ── canonical capability + document/artifact
├── Epic Integration Hub ── Registry references + Epic handoff states
├── Frontend Capability Index ── Registry references used by one FE module
└── Confluence completion document ── result after both sides finish
```

Default relationships:

- One Jira task can create multiple GitHub Issues.
- One GitHub Issue belongs to exactly one primary Jira task.
- One GitHub Issue has one primary owner, one implementation branch, and one PR.
- If an issue needs multiple independent PRs, split the issue before implementation.
- Backend and Frontend Jira items are in two projects, link directly to each
  other, and point to one Epic Integration Hub; do not duplicate the hub across
  two Confluence spaces.
- One Registry capability may be referenced by several Epics and FE module
  indexes without copying its contract.
- Frontend consumes the contract artifact/version published by Backend; it does
  not reconstruct the current contract from multiple issue descriptions or chat.
- Jira moves to `Done` only after required issues are complete and Confluence is
  linked, or documentation is marked `N/A` with a reason.

## Non-negotiable rules

- Issues must have `type`, `area`, and `priority` labels; PRs copy those labels.
- AI adds labels when the mapping is clear. If it is confusing, the agent asks
  the human/manager rather than guessing.
- One branch has only one primary writer at a time.
- AI may review any type of change.
- AI does not approve or merge without human confirmation for that specific PR.
- If validation is incomplete, keep the PR Draft and state what is unverified.
- A Backend change with Frontend impact is handoff-ready only after its contract
  is published, the Registry row and Integration Hub are updated, and the
  linked Frontend issue is notified.
- The initial phase uses manual review and validation; CI or bots are not yet required.

## Documents in this package

| Document | Purpose |
| --- | --- |
| [workflow.md](workflow.md) | Jira → GitHub → Confluence lifecycle and operating checklists |
| [governance.md](governance.md) | Roles, ownership, Ready/Done gates, review, and AI authority |
| [jira-confluence.md](templates/jira-confluence.md) | Copy-paste templates for high-level planning and completion documents |
| [github-issue.md](templates/github-issue.md) | Feature, bug, and technical-task templates |
| [pull-request.md](templates/pull-request.md) | PR description, validation, and approval template |
| [ai-agent-assignment.md](templates/ai-agent-assignment.md) | Vendor-neutral assignment, blocker, and handoff contracts |
| [end-to-end-traceability.md](examples/end-to-end-traceability.md) | Example of a Jira task split into Frontend/Backend issues and PRs |

## When to add automation

Add CI, bots, CODEOWNERS, or GitHub Issue Forms only when recurring process
failures show that manual checklists are no longer enough. Automation must
reinforce this workflow, not create another source of truth.
