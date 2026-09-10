# Development Team and AI Agent Collaboration Workflow

Confluence writes on Codex, Claude and Cursor use native pre/post tool hooks.
See [setup, publication and readback validation](docs/confluence-native-hooks.md).

Beroka governance is a verified, user-scoped release for Codex, Claude, and
Cursor. It supplies workflow context and routes external operations from the
Central repository catalog; it never configures an application repository.

`v1.0.15` is the current supported capability release. Published tags are
immutable.

`Application repository changes: NONE`

`Legacy repository metadata: PRESENT_IGNORED`

## Quick start

Install `gh` and the selected AI client, then run this from any directory.

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

Replace `codex` with `claude` or `cursor` to select another client. The
launcher uses client-owned GitHub OAuth for its private HTTPS clone.
No token is requested, printed, copied, logged, or stored.

Cursor Individual may ask you to install Cursor Agent and confirm its managed
User Rule in **Cursor Settings > Rules**. See the [handbook](handbook.md) for
client prerequisites, connector behavior, and OAuth troubleshooting.

## Add another client

Enrollment is additive. For example, if Codex is already enrolled and you want
to add Claude, run the same launcher for Claude. If the installed release is older than the latest published release, upgrade it first.

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client claude
'
```

Codex remains enrolled and Claude is added alongside it. The same pattern
works for any supported second client: `codex`, `claude`, or `cursor`.
Do not pass `--upgrade` when adding a client to the active release. The flag is
only for changing the active governance release.

## Operate governance

Bootstrap does not infer repository context. At the start of governed work,
select the exact repository explicitly:

```bash
beroka-governance context "$PWD"
```

Run context again after session resume or compaction, when the IDE workspace or current Git repository changes, when another repository enters scope, or when
a plan becomes shared or full-stack.

Run a fresh operation-specific preflight immediately before each external
write:

```bash
beroka-governance preflight "$PWD" \
  --client codex \
  --operation jira-write
```

Bootstrap runs `setup-connectors` for the selected client. If connector or
authentication checks fail, follow the printed remediation and rerun a fresh
preflight. Detailed client commands, result codes, and non-interactive rules
live in the [handbook](handbook.md).

### Add or remove repository governance

Only `beroka-vn/Beroka_Backend` and `beroka-vn/Beroka_Frontend` are in the
default repository catalog. Every other repository is optional and remains
`NOT_GOVERNED` until a user explicitly requests enrollment.

To add a repository, request a reviewed change in this governance repository
that adds its exact canonical GitHub slug as
`runtime/repositories/<owner>/<repository>.conf` with approved profile and
routing values. Merge the catalog change, publish a new immutable release, and
upgrade the user's installation. There is no local `register` command.

To remove a repository, request a reviewed change that deletes its exact
catalog record, publish a new immutable release, and upgrade the user's
installation. Older installed releases keep their pinned catalog until they
are upgraded. Removal only disables governance; it does not delete the GitHub
repository or change files in the application repository. There is no local
`unregister` command.

Folder names, local paths, application-repository files, and unshipped catalog
changes cannot add or remove governance.

## Release lifecycle

### Upgrade

Use `--upgrade` only when moving to a newer same-major release. Enabled clients
and healthy client setup are preserved.

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

Pin an exact newer release with `gh release download vX.Y.Z` when needed. The
launcher embeds the downloaded release; it accepts only `--client`, `--upgrade`, and `--non-interactive`.
In-place `--upgrade` rejects an older target (`VERSION_MISMATCH`).

### Downgrade

To install an older published same-major release, uninstall first and then use
that release's launcher. Example:

```bash
beroka-governance uninstall --force
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download v1.0.10 \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client cursor
'
```

Replace `v1.0.10` and `cursor` with the published release and client you need.
Do not pass `--version`; the release selected by `gh release download` is
already embedded in the launcher.

### Uninstall

Remove user-scoped governance state and managed instruction blocks while
preserving personal text and application repositories:

```bash
beroka-governance uninstall --force
```

See the [handbook](handbook.md) for downgrade and uninstall edge cases.

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

## Team workflow

Backend and Frontend repositories are supported when their canonical origins
have exact Central catalog records:

- Backend: `beroka-vn/Beroka_Backend`
- Frontend: `beroka-vn/Beroka_Frontend`

The catalog selects the approved role, Jira project, and Confluence root.
Agents never infer routing from similar repository names. Use the [operating
workflow](workflow.md), [governance rules](governance.md), and supplied
templates for ownership, readiness, handoff, and Backend Capability Registry
requirements.

## Source of truth

| Record | Owns |
| --- | --- |
| Jira | Outcome, coordination, ownership, status, and links |
| GitHub Issue | Technical scope, criteria, dependencies, and validation |
| Pull Request | Review, validation evidence, approval, and merge history |
| Confluence | Delivered behavior, decisions, guides, and limitations |
| Backend Capability Registry | Canonical cross-Epic capability mapping |

AI never approves or merges without explicit human confirmation for the exact
pull request and commit.

## Documents in this package

| Document | Purpose |
| --- | --- |
| [governance.md](governance.md) | Roles, readiness, authority, and stop conditions |
| [workflow.md](workflow.md) | Jira, GitHub, and Confluence operating sequence |
| [handbook.md](handbook.md) | Client setup, connector health, and release operations |
| [PACKAGE-DESIGN.md](PACKAGE-DESIGN.md) | User-scoped package and release contract |
