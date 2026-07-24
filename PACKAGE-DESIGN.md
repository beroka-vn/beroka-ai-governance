# Beroka AI Governance Package Design

Status: Approved — V1 implementation in review

Approved design discussion: 2026-07-22

Target environments: Linux, macOS, and Windows through WSL

## Problem

The governance documents currently live in one central private repository, but
the agent entrypoints assume that the full document tree is copied into every
application repository. Copying creates version drift and makes removal,
replacement, and controlled upgrades difficult.

The team needs one centrally maintained package that:

- applies only to explicitly registered repositories;
- works with Codex, Claude Code, and Cursor;
- keeps the full governance content outside application repositories;
- pins each registered repository to an immutable reviewed version;
- supports explicit install, update, rollback, unregister, and uninstall;
- preserves stricter repository-specific rules; and
- fails closed when the package or registration is invalid.

## Non-goals

- Automatically applying governance to every repository on a developer machine.
- Background updates, daemons, or silent version changes during an agent task.
- Replacing repository-specific architecture, security, ownership, or validation
  rules.
- Packaging GitHub, Jira, or Confluence credentials.
- Providing native Windows PowerShell support outside WSL in the first release.
- Adding a service, package registry, database, or custom agent protocol.

## Selected approach

Use thin, tracked project entrypoints backed by a locally installed, pinned
release of the central governance repository.

This is the smallest reliable common model because Codex loads `AGENTS.md`,
Claude Code can load `CLAUDE.md` and import `AGENTS.md`, and Cursor loads project
rules from `.cursor/rules`. A global-only loader would affect unrelated
projects, while copying or symlinking the complete package would recreate
version and portability problems.

## Package layout

The central repository will contain:

```text
README.md
VERSION
governance.md
handbook.md
workflow.md
bin/
  beroka-governance
runtime/
  entrypoint.md
templates/
  agent-entrypoints/
examples/
tests/
  connectors.sh
  smoke.sh
```

`bin/beroka-governance` is one POSIX shell CLI. It depends only on standard
POSIX utilities, Git, authenticated access to the private GitHub repository,
and the explicitly selected client. Selected-client
connector inspection requires `jq` for every selected client; Cursor setup also
uses it to preserve user-level MCP JSON. It must not require Python, a daemon,
or a new package manager.

Each release is an immutable annotated SemVer tag. `v1.0.0` is the first public stable release.
After publication, its tag must never be moved or replaced.

## Developer-machine layout

```text
~/.local/bin/beroka-governance
~/.local/share/beroka-ai-governance/releases/v1.0.0/
~/.config/beroka-ai-governance/registered-repos
```

Multiple releases may be installed at the same time so different repositories
can remain pinned independently and rollback does not require a network fetch.
The local registry records only paths, repository slugs, and pinned versions;
it contains no credentials.

## Registered-repository contract

A registered repository contains `.beroka-governance.lock` plus only the
entrypoints listed by its enabled clients:

| Client | Managed entrypoint |
| --- | --- |
| Codex | marker-delimited managed block in root `AGENTS.md` |
| Claude Code | marker-delimited managed block in root `CLAUDE.md` |
| Cursor | `.cursor/rules/beroka-governance.mdc` |

Example lock file:

```text
SOURCE=beroka-vn/beroka-ai-governance
REPOSITORY=beroka-vn/example-backend
VERSION=v1.0.0
COMMIT=0123456789abcdef0123456789abcdef01234567
CLIENTS=codex,claude
```

`CLIENTS` contains at least one of `codex`, `claude`, and `cursor`, has no
duplicates, and uses canonical `codex,claude,cursor` order. The CLI parses only
the five allowlisted keys. It must never `source`, `eval`, or execute the lock
file. A candidate lock without `CLIENTS` is invalid before the first public
release and must be recreated with bootstrap.

Each listed entrypoint contains routing only and independently loads the same
central release. They do not duplicate governance rules or templates. At
session start they require the agent to:

1. resolve the canonical GitHub remote and match it to `REPOSITORY`;
2. read and validate `.beroka-governance.lock`;
3. verify that the matching local release exists and its commit matches the
   lock;
4. run the read-only `beroka-governance context` command to load the central
   entrypoint from that exact release; and
5. continue only when the package reports `PASS`.

An unregistered repository has no lock and no managed entrypoints, so the
package does not apply. A managed block or Cursor rule for an unlisted client
is `ENTRYPOINT_DRIFT`. Repository-specific instructions may narrow central
governance but may not use it to broaden agent authority or bypass a stop
condition. The clients do not need to import or directly read files outside the
workspace; validated package content is emitted through command output.

## CLI lifecycle

### Bootstrap

```bash
beroka-governance bootstrap /path/to/repo --client codex
```

Bootstrap composes the existing install, register, connector setup, and Doctor
operations. For a first interactive registration without `--version`, it uses
a fresh canonical remote query to select the highest latest stable annotated
SemVer tag, prints its exact tag and peeled commit, and requires confirmation.
Pre-releases, lightweight tags, branches, cached refs, and unverified local
checkouts are not candidates.

An existing registration always keeps its exact lock; bootstrap never upgrades
it silently. A conflicting `--version` returns `VERSION_MISMATCH`.
Non-interactive first registration requires explicit `--client` and
`--version`. Every invocation configures exactly one client, never every
detected client. Bootstrap may change only the normal registered-repository
artifacts; it never commits or pushes them.

### Release launcher

Each stable release publishes `bootstrap.sh` as a GitHub Release asset. From a
repository Git root, the supported interactive command is:

```bash
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex
```

The launcher accepts exactly one explicit client, clones its embedded annotated
tag into a temporary directory, verifies that the tag and checked-out HEAD both
match its embedded commit, then invokes that verified release. A mismatch
returns `RELEASE_VERIFICATION_FAILED` before repository or client changes. The
latest URL selects the stable release asset; it never executes `main`.

Repository entrypoints and the lock are shared through Git. The governance CLI,
connector configuration, and OAuth are local to one client in one execution
environment. Setup is repeated once per client per execution environment;
changing a model inside the same client needs no setup. OAuth credentials remain
owned by the client or OS keyring.

### Install

```bash
beroka-governance install v1.0.0
```

The initial bootstrap uses a shallow Git clone of one reviewed tag and runs the
CLI from that checkout. It never pipes network output directly to a shell.

Install authenticates through the developer's existing Git/GitHub setup,
resolves the tag, verifies the tag commit, stages the release in a temporary
directory, and atomically moves it into the release directory. It does not
modify an application repository. Each release remains a shallow, detached Git
checkout so commit identity and local modifications can be verified with Git
instead of a custom integrity format.

The user-level CLI changes only during an explicit install or update. Within a
major version it must remain compatible with every locally installed lock
version. A major CLI or lock-format change requires a coordinated upgrade and
must fail closed when an older CLI cannot interpret the target release.

### Setup connectors

```bash
beroka-governance setup-connectors --client codex
beroka-governance setup-connectors --client claude
beroka-governance setup-connectors --client cursor
```

Setup runs after the selected client and its MCP dependencies are installed.
`--client codex|claude|cursor` selects exactly one client. Running setup again
for another client is explicit and supported; no invocation configures every
installed client.

An interactive invocation without `--client` detects supported executables. It
asks for confirmation when exactly one is found, prompts for one selection when
multiple are found, and returns `DEPENDENCY_MISSING` when none are found. After
registering the Atlassian MCP endpoint, it reports `AUTH_REQUIRED` and asks
before starting that client's OAuth flow.

Interactive OAuth commands remain attached directly to the terminal. The
selected client prints the exact one-time URL or device URL/code; Governance
does not parse, log, or store that output.

Connector health uses a response-driven 15-second total deadline. It stops as
soon as the selected client supplies a complete health record and retries only
safe read-only probes while evidence is incomplete. If no classifiable record
arrives by the deadline, it returns `CONNECTOR_HEALTH_UNAVAILABLE`; unknown
health is never treated as authentication required or as `PASS`.

`--non-interactive` requires explicit client selection and never opens a
browser. Missing, expired, or invalid authentication returns
`ATLASSIAN_AUTH_REQUIRED` and the exact remediation command:

```text
codex mcp login atlassian
claude
In Claude: /mcp -> atlassian -> Authenticate
cursor-agent mcp login atlassian
```

The clients are configured through their own supported paths: Codex app-server
configuration, Claude Code user-scoped MCP commands, and an atomic merge of
Cursor's user-level MCP JSON. Claude authentication runs through interactive
`/mcp`, not a Codex-style `mcp login` subcommand.

`preflight ... --operation github-write` is a separate operation-scoped gate.
It verifies registration, checks `gh auth status --hostname github.com`, and
does not resolve Jira/Confluence routing or inspect Atlassian. Healthy GitHub
auth is reused. Interactive auth-required runs
`gh auth login --hostname github.com --web` after confirmation; non-interactive
mode returns `GITHUB_AUTH_REQUIRED` with that exact remediation command.

### Register

```bash
beroka-governance register /path/to/repo --version v1.0.0 --client codex
```

Register validates the Git repository, uniquely discovered canonical remote,
installed version, the selected entrypoint's clean state, and absence of stale
managed entrypoints for unselected clients. It then creates the lock and merges
only marker-delimited managed content. It never replaces existing repository
rules. Running the same command again is idempotent.

### Doctor

```bash
beroka-governance doctor /path/to/repo
beroka-governance doctor /path/to/repo --client codex
```

Doctor is read-only. It verifies registration, remote identity, tag and commit,
local release integrity, managed entrypoints, and required commands. It prints
the exact active version and a stable result code. Without `--client`, it is
governance-only and does not inspect or trigger OAuth. With `--client`, it also
distinguishes a missing dependency, missing connector, required
authentication, and `PASS`.

### Load agent context

```bash
beroka-governance context /path/to/repo
beroka-governance show /path/to/repo governance
beroka-governance show /path/to/repo template jira-confluence
```

`context` performs the same registration and integrity checks as Doctor, then
prints `runtime/entrypoint.md` from the exact pinned release. `show` prints one
allowlisted root document or template from that release. It rejects absolute
paths, traversal, unknown document names, and arbitrary files. These commands
are read-only and are the only runtime access path required by the three agent
entrypoints.

### Update

```bash
beroka-governance update /path/to/repo --to v1.1.0
```

Update installs the target release if necessary and updates the lock. It
refreshes managed entrypoints only when their format changed. The resulting
application-repository diff is reviewed through its normal pull-request
workflow. Existing agent sessions do not change version; the new release takes
effect in a new session after the update is merged.

### Rollback

```bash
beroka-governance rollback /path/to/repo --to v1.0.0
```

Rollback applies the same checks as update and pins a previously published
release. It does not rewrite or delete release tags.

### Unregister

```bash
beroka-governance unregister /path/to/repo
```

Unregister removes only package markers, the package lock, and the dedicated
Cursor rule. Existing content in `AGENTS.md` and `CLAUDE.md` is preserved. A
file created solely for the managed block may be removed only when no unmanaged
content remains.

### Uninstall

```bash
beroka-governance uninstall
```

Uninstall removes the user-level CLI and releases only when the local registry
contains no registered repositories. `--force` may remove the local package but
does not edit repositories; any remaining entrypoint will then fail closed with
`GOVERNANCE_NOT_READY`.

`register`, `update`, `rollback`, and `unregister` support `--dry-run` and print
the files and versions they would change.

## Version and release policy

- Patch: wording, examples, or template corrections that preserve workflow and
  entrypoint behavior.
- Minor: backward-compatible workflow, template, or CLI capability additions.
- Major: lock format, entrypoint contract, CLI behavior, or governance changes
  that require coordinated repository updates.

A release tag must never be moved or reused. The lock includes both tag and
commit SHA, so a mismatch is an integrity failure rather than an implicit
upgrade. Developers update explicitly; no command automatically selects the
latest tag.

## Failure behavior

The CLI and agent entrypoints use these stable results:

| Result | Meaning |
| --- | --- |
| `GOVERNANCE_NOT_READY` | Required release or valid registration is missing |
| `GOVERNANCE_ACCESS_DENIED` | The central private repository cannot be read |
| `REPOSITORY_NOT_REGISTERED` | No valid lock or managed entrypoint exists |
| `REMOTE_MISMATCH` | The canonical remote does not match `REPOSITORY` in the lock |
| `VERSION_MISMATCH` | Installed tag or commit differs from the lock |
| `ENTRYPOINT_DRIFT` | Managed content was changed outside the CLI |
| `WORKTREE_CONFLICT` | A target entrypoint has uncommitted changes |
| `DEPENDENCY_MISSING` | The selected client or required client command is missing |
| `CONNECTOR_MISSING` | The selected client lacks the expected Atlassian connector |
| `ATLASSIAN_AUTH_REQUIRED` | Atlassian OAuth is missing, expired, or invalid |
| `AUTH_PENDING` | Registration succeeded but interactive OAuth was declined or incomplete |
| `CONNECTOR_HEALTH_UNAVAILABLE` | No classifiable connector health arrived before the deadline |
| `GITHUB_AUTH_REQUIRED` | GitHub OAuth is missing, expired, or invalid for `github-write` |
| `PASS` | All checks requested by the command passed |

No failed command may leave a partial registration or version change. The CLI
computes and validates the complete change set before writing, uses temporary
files and atomic replacement, and restores original files if a later write
fails. Unrelated dirty files do not block an operation; dirty package-owned
targets do.

## Security boundaries

- The package stores no GitHub, Jira, Confluence, or agent credentials.
- Atlassian OAuth state and credentials remain owned by the selected client or
  OS keyring. The CLI never accepts, requests, prints, logs, or stores a
  developer API token.
- GitHub OAuth state and credentials remain owned by GitHub CLI or the OS
  keyring. Governance runs the provider login process directly and never
  captures its one-time URL, device code, or credentials.
- Private-repository access uses each developer's existing least-privilege Git
  or GitHub authentication.
- The release launcher asset itself is invoked through `curl | sh`. Before it
  runs the package CLI, it clones and verifies its embedded annotated tag,
  peeled commit, and exact checked-out HEAD; it does not claim checksum or
  signature verification that is not implemented. The CLI never executes a
  lock file or fetches an unpinned branch for runtime use.
- Only reviewed tags are installable by default.
- Central repository `Read` users may clone releases but cannot publish or move
  tags.
- Governance instructions are guidance, not an authorization mechanism.
  Repository permissions, sandboxing, hooks, and human approvals remain the
  enforcement boundary.

## Validation

`tests/smoke.sh` creates temporary Git repositories and verifies at least:

- install and register success;
- idempotent repeated registration;
- preservation of pre-existing `AGENTS.md` and `CLAUDE.md` content;
- exact lock/tag/commit validation;
- refusal when an installed release checkout has local modifications;
- validated `context` and allowlisted `show` output;
- update and rollback between two fixture releases;
- unregister without deleting unmanaged content;
- detection of modified lock and managed blocks;
- refusal on remote mismatch and dirty managed targets; and
- no repository mutation after a failed preflight.

`tests/connectors.sh` uses temporary HOME/XDG directories and fake client
executables. It verifies exact client selection, registration preservation,
per-client OAuth delegation, non-interactive remediation, Doctor result
classification, and that governance-only Doctor makes no connector call. It
uses no real credential.

The release gate is:

```bash
sh -n bin/beroka-governance
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
```

Routing runs from a clean clone:

```bash
routing_clone=$(mktemp -d "${TMPDIR:-/tmp}/beroka-routing-final.XXXXXX")
git clone -q --no-local . "$routing_clone/repo"
git -C "$routing_clone/repo" checkout -q HEAD
sh "$routing_clone/repo/tests/routing.sh"
```

Before publishing a release, a maintainer also starts fresh sessions and
records:

- Codex loaded its managed `AGENTS.md` and exact pinned release;
- Claude Code loaded its managed `CLAUDE.md` and exact pinned release; and
- Cursor shows and applies its dedicated project rule and exact pinned release.

The same POSIX script is validated on Linux, macOS, and WSL. No tag is published
until every automated suite and the three independent client checks pass on the
tagged commit.

## Acceptance criteria

- Every client listed in `CLIENTS` loads the same exact central governance
  release.
- An unregistered repository does not load the package.
- The full governance document tree is absent from application repositories.
- Existing repository instructions survive register, update, rollback, and
  unregister unchanged outside managed markers.
- Updates are explicit, auditable diffs and never alter an active agent session.
- Rollback restores a previously tagged version without network access when the
  release is already installed.
- Doctor identifies every supported drift and access failure with a stable
  result.
- Connector setup configures exactly one selected client, delegates OAuth to
  that client, and fails closed without browser access in non-interactive mode.
- Unregister and uninstall remove package-owned state without deleting user or
  repository-owned content.

## Initial rollout

Implement and release the package from the central governance repository. The
first public rollout supports explicit Backend and Frontend repository
registration. Each repository keeps an independent pinned lock and routing
configuration. Do not bulk-register repositories or add silent update
automation.

## Compatibility references

- [Codex `AGENTS.md`](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Claude Code memory and `CLAUDE.md`](https://code.claude.com/docs/en/memory)
- [Cursor project rules](https://docs.cursor.com/context/rules)
