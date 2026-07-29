# Development Team and AI Agent Collaboration Workflow

Beroka governance is a verified, user-scoped release for the selected AI
client. It supplies workflow context and routes external operations from the
Central repository catalog; it does not configure the application repository.

## Quick start

Install the selected AI client and `gh` once per workstation. Run this from any
directory. Healthy client-owned GitHub OAuth is reused; when it is missing,
`gh` starts its browser OAuth flow and keeps credentials in its own store.

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
and confirm it when bootstrap asks. Governance never edits Cursor's internal
settings database.

Run setup for one client on each execution environment, then repeat it only
when you want to enroll another client there.

Bootstrap runs `setup-connectors` for the selected client. If authentication
is still pending, rerun
`beroka-governance setup-connectors --client codex`; interactive login streams
provider OAuth output directly, while `--non-interactive` returns the exact
client-owned remediation without opening a browser.

The launcher verifies its embedded annotated tag and commit before it executes
package code. It installs the active release and selected-client adapter in
user-owned locations. Bootstrap does not infer repository context from the
current directory; run `beroka-governance context "$PWD"` explicitly when
governed repository work begins.

`Application repository changes: NONE`

`Legacy repository metadata: PRESENT_IGNORED`

Tracked legacy governance files remain until a repository owner explicitly
authorizes a separate cleanup. The new CLI ignores them for release selection
and routing. `v1.0.0` is the current supported capability release. Every
published tag is immutable.

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
