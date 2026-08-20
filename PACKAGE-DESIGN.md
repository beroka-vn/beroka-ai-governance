# Beroka AI Governance Package Design

Status: Approved — user-scope release contract

## Problem and selected approach

Governance installation used to mix workstation setup with application-repository configuration. The active release and enabled clients are now user-owned. A verified release contains workflow documents and the Central repository catalog, which maps a canonical GitHub origin to exact routing.

`Application repository changes: NONE`

`Legacy repository metadata: PRESENT_IGNORED`

Legacy tracked governance files are neither parsed nor changed. They remain until a repository owner explicitly authorizes cleanup. The application repository is read only for canonical-origin discovery; it never selects an active governance version or routing record.

## User-owned state

```text
~/.local/bin/beroka-governance
~/.local/share/beroka-ai-governance/releases/<version>/
~/.config/beroka-ai-governance/active-release
~/.config/beroka-ai-governance/clients
```

The active release record and client enrollment are the source of installation
state. No credential is stored there.
`v1.0.13` is the current supported capability release.

The release catalog is keyed by normalized canonical GitHub slug. Its reviewed record supplies profile, Jira project and board, Confluence root, integration profile, and cross-repository policy. An unknown origin is standalone with `ROUTING_REQUIRED`: source-only work may continue, but routing-dependent writes remain blocked. Catalog changes require an explicitly authorized governance-repository task.

The supported BE/FE boundary contains only
`beroka-vn/Beroka_Backend` and
`beroka-vn/Beroka_Frontend`. Both select `beroka-be-fe`; this emits
the compact shared work-item rules but does not authorize automatic
cross-repository writes.

Bootstrap derives one user-scoped `FE`, `BE`, or `FULL_STACK` role from exact
`beroka-vn` GitHub Team membership. Context enforces the stored role locally;
eligible preflights revalidate membership before external writes. `FULL_STACK`
may open the exact Backend+Frontend catalog pair in Cursor. Governed multi-root
writes select BE or FE from a unique structured BB/BF project (or unambiguous
repository target); name heuristics ignore `workspace_roots` path strings so
product-folder clones do not force `TARGET_REQUIRED`. Cursor hooks append the
user bin (`~/.local/bin`) to `PATH` only when `cursor-agent` or `gh` is missing,
preserving earlier executable precedence.

## Client adapters and enforcement

Bootstrap enrolls exactly one of `codex`, `claude`, or `cursor`. Codex and Claude receive marker-delimited managed blocks in their user instruction files; content outside those blocks is preserved. Existing healthy client setup is left unchanged.

Cursor bootstrap uses an atomic JSON merge for documented global local hooks;
personal hooks are preserved. Cursor Individual still confirms the printed User
Rule in **Cursor Settings > Rules**; non-interactive setup without confirmation
returns `CURSOR_USER_RULE_REQUIRED`. Doctor separately reports `Instruction:
USER_CONFIRMED`, `Runtime hook: INSTALLED`, and `Runtime enforcement: PASS`.
Security hooks fail closed for governed MCP and shell write events. Receipts at
`XDG_STATE_HOME/beroka-ai-governance/cursor` use a hashed conversation filename
and contain only workspace, repository, generation, release identity, and
language. The runtime-enforcement canary verifies the installed hook boundary.
The local-agent threat model covers Cursor-initiated actions only; it does not
protect a compromised user account or unrelated local processes.

CLI hard-enforces installation, release integrity, catalog routing, connector, authentication, and operation preflight. Agent instructions govern workflow behavior unless CI, hooks, branch protection, or platform policy provides hard enforcement.

### Release launcher

Each stable release publishes `bootstrap.sh` as a GitHub Release asset. `gh`
and a selected Codex or Claude client are workstation prerequisites.
Interactive Cursor bootstrap installs a missing Cursor Agent after one
confirmation. The compact install command is the only public install path:

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

`gh auth setup-git --hostname github.com` reuses client-owned GitHub OAuth for the private HTTPS clone. No token is requested, printed, copied, logged, or stored. The downloaded release launcher clones the embedded annotated tag and invokes the package CLI only after tag type, peeled commit, and checked-out HEAD each equal the embedded commit. A mismatch returns `RELEASE_VERIFICATION_FAILED` before user-state changes.

After verification, bootstrap installs the active release, enrolls the selected client, and configures only that client's connector. Bootstrap does not infer repository context from the current directory; callers run `beroka-governance context REPO` explicitly when governed repository work begins. Missing `jq` or `curl` may be installed interactively with `apt-get`, `dnf`, or `brew`; declining returns `DEPENDENCY_MISSING`. Cursor Agent is downloaded only from `https://cursor.com/install`, staged completely, and executed with `bash`.

### Upgrade

The only public upgrade path preserves enabled clients and changes only verified user-owned state:

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

Automation preinstalls the selected client, `gh`, and `jq`, and fails closed instead of opening a browser:

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

## Runtime, connector, and safety contract

At a new session, resume, or compaction, run `beroka-governance context "$PWD"` before governed planning, implementation, or external actions. Rerun it when the IDE workspace or current Git repository changes, another repository enters scope, or planning becomes shared/full-stack; shared work resolves every exact target and one primary tracking repository. Immediately before an external write, run the matching operation preflight. The selected client owns OAuth. Governance does not accept, print, log, or store a developer API token.

Connector health uses a 15-second total deadline. Missing, expired, or invalid Atlassian authentication returns `ATLASSIAN_AUTH_REQUIRED` with selected-client remediation. `CONNECTOR_HEALTH_UNAVAILABLE` is not authentication success or `PASS`. Interactive provider output stays attached to the terminal.

Once authentication is known to be missing, expired, or invalid, interactive
setup, bootstrap, and preflight start re-authentication immediately and wait
for the selected producer: `codex mcp login atlassian`,
`claude mcp login atlassian --no-browser`, or
`cursor-agent mcp login atlassian`. Claude checks
`claude mcp login --help` for `--no-browser` only at this OAuth boundary;
unsupported clients return `DEPENDENCY_MISSING` with
`Remediation: claude update`. Non-interactive setup, bootstrap, and preflight
and all Doctor paths never invoke login. Cursor hooks retain their
non-interactive preflight contract.

An active agent receiving `ATLASSIAN_AUTH_REQUIRED` stops the dependent write,
runs the selected command in an interactive terminal, streams producer output
so the user receives the one-time login URL, and waits for completion. It
never synthesizes, parses, persists, or copies that URL or credentials into an
issue, commit, or durable log. It reruns a fresh operation-specific preflight
and continues only on `Result: PASS`.

Cursor MCP commands run from `/` while preserving the user's HOME and
credentials. This keeps global `~/.cursor/mcp.json` separate from a
project-local `.cursor/mcp.json`, including when bootstrap is invoked from
HOME.

Interactive Cursor first-run confirms before writing only the global Atlassian
MCP entry, streams OAuth, then health-checks. A project connector is reported
as `Project MCP: PRESENT_IGNORED` and is neither modified nor accepted as
global setup. Non-interactive Cursor first-run does not write global MCP configuration
or start OAuth; it returns the interactive resume command. Compatible global
connectors remain idempotent and unknown health remains fail-closed.

Bootstrap invokes `setup-connectors` for its selected client. The selected
client's connector inspection requires `jq` for every selected client.

schema-1 compatibility remains for earlier releases. `provider-owned evidence` is the capability baseline; `cross-client adapters` normalize only the inventory returned by Codex, Claude Code, or Cursor. Workflow rules are instruction-driven and are not hard CLI enforcement.

Before a Jira create, resolve exact metadata and search the intended record. Create once, then read back the key; an indeterminate result is `CREATION_STATUS_UNKNOWN` and is never retried automatically. Confluence writes also read back content and parent. Ordinary Confluence create/move use `confluence-page-parent-write`. Writes are allow-by-default except release-hardcoded `UNACTIVATED` targets (`DOCS_UNACTIVATED`) and missing handoff delta markers (`HANDOFF_DELTA_REQUIRED`).

## Version, security, and validation

Release tags are immutable annotated SemVer. The active release validates its tag and commit, not a branch, cached ref, or local repository metadata. The package stores no GitHub, Jira, Confluence, or agent credential; provider permissions and platform controls remain enforcement boundaries.

The release gate is:

```bash
sh -n bin/beroka-governance
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
sh tests/cursor-hooks.sh
sh tests/documentation-architecture.sh
sh tests/release.sh
```

Central release and catalog publication are separate, explicitly authorized governance-repository work. They are never a side effect of application work.
