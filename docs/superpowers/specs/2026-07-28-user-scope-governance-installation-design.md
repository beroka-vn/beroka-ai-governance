# User-Scope Governance Installation Design

**Date:** 2026-07-28
**Status:** Approved

## Problem

The current bootstrap flow combines workstation installation with repository
configuration. It writes `.beroka-governance.lock` and agent entrypoints into
the application repository, then requires developers to review and commit
those files. A later governance release changes the repository pin and may
require another application pull request even though no application behavior
changed.

That is the wrong ownership boundary. Installing or upgrading governance must
behave like installing an AI client: it changes user-owned tooling and client
configuration, not the repository being worked on.

## Goals

- Keep the application repository byte-for-byte unchanged during bootstrap,
  upgrade, connector setup, Doctor, and context loading.
- Install the governance package, release state, and client enrollment in
  user-owned locations.
- Apply one shared governance workflow to Codex, Claude Code, and Cursor
  without overwriting personal instructions.
- Resolve repository policy from the canonical GitHub origin and a central
  catalog shipped in the verified governance release.
- Preserve client- and OS-owned OAuth credentials.
- Keep explicit client selection and fail-closed non-interactive behavior.

## Non-goals

- Automatically modifying, committing, pushing, or opening a pull request in
  an application repository.
- Programmatically editing Cursor's undocumented internal settings database.
- Removing legacy tracked governance files from application repositories.
- Making model instructions equivalent to CI, hooks, branch protection, or
  platform permissions.
- Automatically changing the central repository catalog.

## Ownership model

Governance has three separate ownership scopes:

1. The verified release owns central principles, profiles, compatibility
   records, templates, and the canonical repository catalog.
2. The workstation owns installed releases, selected-client enrollment,
   connector configuration, authentication, acknowledgements, and caches.
3. The application repository owns only application source and any
   repository-specific instructions that its maintainers deliberately choose
   to commit.

Bootstrap and upgrade operate only in the first two scopes. They treat the
third scope as read-only.

## User-owned state

The existing XDG-aware installation locations remain authoritative:

```text
$XDG_DATA_HOME/beroka-ai-governance/releases/<version>/
$XDG_CONFIG_HOME/beroka-ai-governance/
$XDG_CACHE_HOME/beroka-ai-governance/
```

The config directory records enabled clients and Cursor User Rule
acknowledgement. The cache may hold read-only remote verification data. Neither
location contains OAuth credentials or developer API tokens.

There is no repository lock. The active governance version is the verified
user-installed release. Application repositories do not pin governance
versions.

## Central repository catalog

Each release contains an allowlisted catalog keyed by normalized canonical
GitHub repository slug. A catalog record contains the existing routing schema:

```text
SCHEMA_VERSION
PROFILE
JIRA_PROJECT_KEY
JIRA_BOARD_ID
CONFLUENCE_SPACE_KEY
CONFLUENCE_ROOT_CONTENT_ID
CONFLUENCE_ROOT_CONTENT_TYPE
INTEGRATION_PROFILE
CROSS_REPO_POLICY
```

Optional operation fields remain optional. Folder and board operations still
require the corresponding runtime connector capability.

The release tag and commit verification protect the catalog together with the
rest of the package. Adding a repository or changing durable routing is a
reviewed change to the governance repository, never an automatic change to the
application repository.

An unknown repository receives:

```text
PROFILE=standalone
DEPENDENCY_STATE=NO_DEPENDENCY_DECLARED
CROSS_REPO_POLICY=explicit-only
Routing: ROUTING_REQUIRED
```

Source-only work may continue. External routing-dependent writes remain
blocked until an exact central catalog record exists.

## Client adapters

### Codex

Bootstrap writes only the managed Beroka block in the active global Codex
instruction file under `CODEX_HOME`, normally `~/.codex/AGENTS.md`. If a
non-empty `AGENTS.override.md` is active, the managed block belongs there
instead. Content outside the markers is preserved. A malformed or conflicting
managed block returns `CLIENT_INSTRUCTION_CONFLICT`.

### Claude Code

Bootstrap writes only the managed Beroka block in
`~/.claude/CLAUDE.md`. Content outside the markers is preserved. A malformed
or conflicting managed block returns `CLIENT_INSTRUCTION_CONFLICT`.

### Cursor

Cursor Individual exposes User Rules through the settings UI but no supported
CLI or file interface for managing them. Bootstrap therefore never edits
Cursor's internal database.

Interactive setup prints the exact stable Beroka User Rule, asks the developer
to add it once, and records only their acknowledgement. Non-interactive setup
returns:

```text
Result: CURSOR_USER_RULE_REQUIRED
```

with exact remediation. Doctor reports the instruction state as
`USER_CONFIRMED`, not `VERIFIED`. A future change to the stable adapter text
invalidates the acknowledgement and requires confirmation again.

## Bootstrap and upgrade

The public launcher retains exact release tag and commit verification, then
invokes one user-scope operation:

```text
bootstrap.sh --client codex|claude|cursor [--upgrade] [--non-interactive]
```

Bootstrap:

1. verifies the release;
2. installs it into user-owned storage;
3. enrolls exactly the selected client;
4. installs or confirms that client's user-scope adapter;
5. configures only that client's connector;
6. starts client-owned OAuth only when required and interactive; and
7. renders context for the current Git repository when one exists.

Bootstrap does not require the current directory to be a Git repository.

Upgrade replaces only the verified user-owned package and cache. It preserves
all enabled clients and OAuth state. Omitting `--upgrade` when a newer release
is required returns `GOVERNANCE_UPGRADE_REQUIRED` with the exact command.
Upgrade never creates a repository version change.

Running setup later for another client enrolls only that client and leaves
existing client adapters unchanged.

## Session flow

At session start, resume, or post-compaction:

```text
resolve Git root and canonical origin
→ load the verified installed release
→ find the exact central catalog record
→ select only the required profile and integration pack
→ render effective boundaries
→ execute the requested workflow
```

Fresh operation-specific preflight remains required before external writes.
Governance operations that do not require external connectors do not check or
trigger OAuth.

## Repository immutability

For bootstrap, upgrade, setup-connectors, Doctor, context, and preflight:

- no repository file is created, changed, or deleted;
- the index is not changed;
- no branch is created or switched;
- no commit, push, Issue, or pull request is created; and
- dirty, detached, behind, or feature-branch state does not block user-scope
  installation.

The following former result is retired from bootstrap and upgrade:

```text
Repository pull request: REQUIRED
```

The claim that an application repository must update its governance lock on
`main` is explicitly invalid because the repository no longer owns a
governance version.

## Legacy migration

Existing tracked `.beroka-governance.lock`, `AGENTS.md`, `CLAUDE.md`, or Cursor
rule files are not automatically removed or changed. The new CLI does not use a
legacy lock as its effective version or routing source and reports:

```text
Legacy repository metadata: PRESENT_IGNORED
```

Legacy managed entrypoints may continue to call `beroka-governance context`;
the user-scope adapter is authoritative. Their presence does not produce
`VERSION_MISMATCH`, `WORKTREE_CONFLICT`, or a pull-request requirement.

Repository owners may request a separate cleanup change later. Governance must
never create that change without explicit authorization for the exact
repository and scope.

The repository-mutating `register`, `update`, `rollback`, and `unregister`
commands are retired. They return `COMMAND_RETIRED` with user-scope or central
catalog remediation and do not alter the repository.

## Authentication and security

- GitHub authentication is used to download and verify the private release.
- Bootstrap and upgrade perform no GitHub write operation.
- Atlassian authentication remains owned by the selected client and OS
  keyring.
- Interactive mode may open the client-supported browser OAuth flow.
- Non-interactive missing or invalid Atlassian authentication returns
  `ATLASSIAN_AUTH_REQUIRED` with exact remediation.
- No developer API token is accepted, printed, logged, or stored.
- Client commands remain client-specific; Codex, Claude Code, and Cursor are
  not assumed to share authentication commands.

## Doctor results

Doctor distinguishes at least:

```text
DEPENDENCY_MISSING
CLIENT_INSTRUCTION_REQUIRED
CLIENT_INSTRUCTION_CONFLICT
CURSOR_USER_RULE_REQUIRED
CONNECTOR_MISSING
ATLASSIAN_AUTH_REQUIRED
ROUTING_REQUIRED
CONNECTOR_CAPABILITY_REQUIRED
PASS
```

Cursor acknowledgement is displayed separately from connector and
authentication health so `USER_CONFIRMED` is never misreported as runtime
verification.

## Test strategy

Tests use temporary HOME, XDG, Git config, repositories, client binaries, and
credential-free connector fixtures.

They must prove:

1. First install leaves a clean application repository unchanged.
2. Install and upgrade leave modified, untracked, deleted, detached, behind,
   and feature-branch repositories unchanged.
3. Repository status, tracked blobs, index, HEAD, branch, and untracked file
   hashes match before and after each user-scope command.
4. Legacy locks and entrypoints are ignored without version mismatch,
   worktree conflict, or pull-request output.
5. Codex and Claude managed blocks preserve all personal content and remain
   idempotent.
6. Cursor interactive acknowledgement is user-owned; non-interactive setup
   fails closed without editing Cursor state.
7. Adding a second client does not reconfigure or reauthenticate a healthy
   first client.
8. Missing, expired, and invalid authentication uses the exact selected-client
   remediation and never requests a token.
9. Central catalog lookup selects the exact canonical repository and never
   guesses routing from repository names.
10. Unknown repositories remain source-capable and routing-dependent writes
    return `ROUTING_REQUIRED`.
11. Existing connector, capability, routing, documentation architecture, and
    release verification suites remain green.

## Acceptance criteria

- The documented install and upgrade commands cause zero application
  repository changes.
- A governance release upgrade never requires an application repository pull
  request.
- Codex and Claude receive governance through preserved global managed blocks.
- Cursor Individual receives a one-time exact User Rule workflow without
  unsupported database edits.
- All repository routing comes from the verified central catalog.
- OAuth and credentials remain client- and OS-owned.
