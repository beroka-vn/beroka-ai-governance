# Development Team and AI Agent Collaboration Workflow

Beroka governance is a verified, user-scoped release for the selected AI
client. It supplies workflow context and routes external operations from the
Central repository catalog; it does not configure the application repository.

## Quick start

Install `gh` and the selected Codex or Claude client once per workstation.
Interactive Cursor bootstrap installs a missing Cursor Agent after one
confirmation. Run this from any directory. Healthy client-owned GitHub OAuth
is reused; when it is missing, `gh` starts its browser OAuth flow and keeps
credentials in its own store.

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex
'
```

`gh auth setup-git --hostname github.com` configures Git to reuse
client-owned GitHub OAuth for the launcher's private HTTPS clone. No token is requested, printed, copied, logged, or stored.

Replace `codex` with `claude` or `cursor` to enroll exactly that client.
Existing healthy client setup is preserved. Cursor Individual requires a
one-time confirmation: add the printed User Rule in **Cursor Settings > Rules**
and confirm it when bootstrap asks. Cursor bootstrap atomically installs
documented global local hooks while preserving personal hooks; Governance never
edits Cursor's internal settings database. For Cursor, Doctor reports
`Instruction: USER_CONFIRMED`, `Runtime hook: INSTALLED`, and `Runtime
enforcement: PASS`.

Run setup for one client on each execution environment, then repeat it only
when you want to enroll another client there.

Bootstrap runs `setup-connectors` for the selected client. Once Atlassian
authentication is known to be missing, expired, or invalid, interactive
setup, bootstrap, and preflight start the selected producer's
re-authentication immediately and wait for it to finish:

```text
Codex:  codex mcp login atlassian
Claude: claude mcp login atlassian --no-browser
Cursor: cursor-agent mcp login atlassian
```

Interactive authentication treats producer output as opaque and passes
provider OAuth output directly to the terminal so the user receives its
one-time login URL.

Claude checks `claude mcp login --help` for `--no-browser` only at this OAuth
boundary. Without it, governance returns `DEPENDENCY_MISSING` with
`Remediation: claude update`. Non-interactive setup, bootstrap, and preflight
and all Doctor paths never invoke login; Cursor hooks retain non-interactive
preflight. Interactive Cursor first-run still asks
`Install global Atlassian MCP and start OAuth now?` before writing the global
MCP configuration, then starts OAuth without another confirmation.

An active agent receiving `ATLASSIAN_AUTH_REQUIRED` stops the dependent write,
runs the selected command in an interactive terminal, streams producer output
so the user receives the one-time login URL, and waits for completion. It
never synthesizes, parses, persists, or copies that URL or credentials into an
issue, commit, or durable log. It then runs a fresh operation-specific
preflight and continues only on `Result: PASS`.

The launcher verifies its embedded annotated tag and commit before it executes
package code. It installs the active release and selected-client adapter in
user-owned locations. Bootstrap does not infer repository context from the
current directory; run `beroka-governance context "$PWD"` explicitly when
governed repository work begins.

`Application repository changes: NONE`

`Legacy repository metadata: PRESENT_IGNORED`

Tracked legacy governance files remain until a repository owner explicitly
authorizes a separate cleanup. The new CLI ignores them for release selection
and routing. `v1.0.10` is the current supported capability release. Every
published tag is immutable.

### v1.0.10 release

This release makes Confluence documentation **allow-by-default**. Ordinary
create/update/move uses `confluence-page-parent-write` and is allowed unless the
target or parent is listed as `UNACTIVATED` in the pinned release inventory
(`DOCS_UNACTIVATED`; only a reviewed governance release PR can change that
list). Create/update bodies must include handoff delta markers (`Jira:`,
`GitHub:`, and a `## Handoff —` section or `Handoff form: child-page` with
`Canonical:`) or return `HANDOFF_DELTA_REQUIRED`. Moves require a numeric
destination parent. Hierarchy bootstrap remains optional guidance. Cursor hooks
also parse stringified MCP `tool_input` JSON so governed writes do not
false-deny with empty fields.

It also fixes FULL_STACK Cursor multi-root target selection when workspace
folder paths literally contain `Beroka_Backend` and `Beroka_Frontend`. Unique
`projectKey` / parent / epic keys (BB or BF) select that side even though both
product names appear in `workspace_roots`, so targeted `createJiraIssue` writes
clear `TARGET_REQUIRED`. Hook PATH appends the user bin as a fallback when
`cursor-agent` or `gh` is missing, so templated `gh` creates do not false-fail
`DEPENDENCY_MISSING` when those tools live under `~/.local/bin`, without
shadowing an earlier healthy executable. Upgrades from v1.0.9 no longer fail
with `Invalid Confluence target inventory` on traditional awk (common on macOS)
when multiple repository `CONFLUENCE_ROOT_CONTENT_ID` values are joined for
inventory validation. Official Atlassian MCP field aliases
from v1.0.9 (`issueTypeName`, `assignee_account_id`, `Missing:` hints) remain
required.

### v1.0.10 upgrade

Bootstrap installs a missing Cursor Agent after one confirmation. Developers
upgrading from `v1.0.0` through `v1.0.9` run this once; installation and
Atlassian connector setup continue in the same process:

```bash
bash -e -o pipefail -c 'gh release download v1.0.10 --repo beroka-vn/beroka-ai-governance --pattern bootstrap.sh --output - | sh -s -- --client cursor --upgrade'
```
To select the current repository immediately after upgrading, run:
```bash
beroka-governance context "$PWD"
```

### Upgrade

Use the single upgrade path when a newer same-major release is published. It
replaces only verified user-owned governance state and preserves enabled
clients and their healthy setup:

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex --upgrade
'
```

### Automation / CI

Automation never installs packages or opens a browser. Preinstall the selected
client, `gh`, and `jq`, authenticate `gh`, then use:

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 || {
    printf "%s\n" \
      "Result: GITHUB_AUTH_REQUIRED" \
      "Remediation: gh auth login --hostname github.com --web" >&2
      exit 1
  }
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex --non-interactive
'
```

In a fresh session, run `beroka-governance context "$PWD"` before governed
planning, implementation, or external actions. Run the operation-specific
preflight immediately before each external write. Unknown repositories may do
source-only work but return `ROUTING_REQUIRED` for routing-dependent writes.
Rerun context when the IDE workspace or current Git repository changes, another
repository enters scope, or a plan becomes shared/full-stack. Shared planning
requires exact targets, context for each target, and one primary tracking
repository.

```bash
beroka-governance preflight "$PWD" \
  --client codex \
  --operation jira-write
```

The active release resolves the canonical GitHub origin against the Central
repository catalog. Catalog additions or routing changes require an explicitly
authorized governance-repository task; application repositories do not alter
the catalog.

## Team workflow

Backend and Frontend repositories are both supported when their canonical
origins have exact catalog records. The catalog selects the approved profile,
integration, Jira project, board, and Confluence root; never infer one from a
similar repository name.

- Backend: `beroka-vn/Beroka_Backend`.
- Frontend: `beroka-vn/Beroka_Frontend`.

Bootstrap derives `FE`, `BE`, or `FULL_STACK` from exact `beroka-vn` GitHub
Team membership. Context denies a routed profile outside that stored role, and
eligible preflights revalidate membership before external writes. `FULL_STACK`
may open a Cursor multi-root workspace that contains exactly the catalog
`Beroka_Backend` and `Beroka_Frontend` pair; governed writes must name the exact
BB/BF project, parent/epic key, or repository target. Target selection prefers
that structured project and does not treat `workspace_roots` folder path
substrings as BE/FE signals, so real product-folder clones do not force
`TARGET_REQUIRED`. Untargeted FULL_STACK writes still return `TARGET_REQUIRED`.
When `origin` is a fork, governance prefers another remote whose slug has an
exact catalog record (for example `beroka` or `upstream`). Multiple remotes for
the same catalog slug are accepted and prefer `origin`. Unknown repositories
stay source-only and never inherit BE/FE routing.

- Manager/coordinator: use the [operating workflow](workflow.md), then the
  [Jira and Confluence template](templates/jira-confluence.md) and [GitHub
  Issue template](templates/github-issue.md).
- Developer: use the [governance rules](governance.md), accept work that meets
  the Definition of Ready, and use the [Pull Request
  template](templates/pull-request.md).
- AI agent: use the [AI Agent Assignment
  Template](templates/ai-agent-assignment.md).

## Source of truth

| Record | Owns |
| --- | --- |
| Jira | Outcome, coordination, ownership, status, and links |
| GitHub Issue | Technical scope, criteria, dependencies, and validation |
| Pull Request | Review, validation evidence, approval, and merge history |
| Confluence | Delivered behavior, decisions, guides, and limitations |
| Backend Capability Registry | Canonical cross-Epic capability mapping |

Use one primary issue owner, branch, and pull request. The workflow remains
instruction-driven: CI, hooks, branch protection, and platform permissions are
the only hard enforcement when they exist. AI never approves or merges without
explicit human confirmation for the exact pull request and commit.

## Documents in this package

| Document | Purpose |
| --- | --- |
| [governance.md](governance.md) | Roles, readiness, authority, and stop conditions |
| [workflow.md](workflow.md) | Jira, GitHub, and Confluence operating sequence |
| [handbook.md](handbook.md) | Client setup, connector health, and release gate |
| [PACKAGE-DESIGN.md](PACKAGE-DESIGN.md) | User-scope package and release contract |
