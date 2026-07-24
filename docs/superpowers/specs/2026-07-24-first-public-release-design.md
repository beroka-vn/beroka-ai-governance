# First Public Release Design

**Status:** Approved for local release preparation

**Release:** `v1.0.0`

**Date:** 2026-07-24

## Goal

Publish the first stable Beroka AI Governance release with one copy-paste
bootstrap flow for explicitly selected Backend or Frontend repositories.
Prepare and verify everything locally, then stop and show the developer
workflow and exact release commit before any GitHub push.

## Release identity

- `v1.0.0` is the first public stable release.
- The existing local `v1.0.0` tag is an unpublished test candidate. It may be
  deleted locally only after the final release commit passes every gate.
- No `v1.0.0` tag currently exists on the canonical GitHub remote.
- The final tag is annotated and points to the exact reviewed release commit.
- After publication, `v1.0.0` is immutable and must never be moved or replaced.
- The unpublished local `v1.1.0` candidate is not part of this release and must
  not be pushed.

## Supported repository scope

- Backend and Frontend repositories are both supported.
- Each bootstrap invocation registers exactly one explicit Git repository.
- Running bootstrap later in another repository is supported and explicit.
- Governance never scans for or automatically registers every local repository.
- Repository-specific routing remains required for Jira, Confluence, and
  cross-repository writes. Bootstrap does not invent routing.

## Developer bootstrap

The published quick start is one copy-paste block run from the target
application repository:

```bash
repo=$(git rev-parse --show-toplevel)
bootstrap_dir=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-bootstrap.XXXXXX")

git clone --depth 1 --single-branch --branch v1.0.0 \
  https://github.com/beroka-vn/beroka-ai-governance.git \
  "$bootstrap_dir/repo"

sh "$bootstrap_dir/repo/bin/beroka-governance" bootstrap "$repo"
```

Interactive bootstrap:

1. resolves the canonical target repository;
2. detects installed Codex, Claude Code, and Cursor clients;
3. asks for confirmation when exactly one client is detected;
4. offers a numbered selection when multiple clients are detected;
5. resolves the latest stable annotated release, shows its exact version and
   commit, and asks before installation;
6. installs the CLI and pinned release;
7. registers only the target repository;
8. configures only the selected client connector;
9. offers the selected client's OAuth flow only when authentication requires
   it; and
10. runs governance Doctor and client-aware Doctor.

The explicit-client form remains available:

```bash
sh "$bootstrap_dir/repo/bin/beroka-governance" bootstrap \
  "$repo" --client codex
```

Automation must remove every ambiguity:

```bash
sh "$bootstrap_dir/repo/bin/beroka-governance" bootstrap \
  "$repo" \
  --client codex \
  --version v1.0.0 \
  --non-interactive
```

## Missing context and decision ownership

Governance and AI agents must not guess a repository, client, release,
connector target, Jira project, Confluence parent, or cross-repository mapping.

- Interactive mode presents safe detected choices and asks the developer.
- No detected client returns `DEPENDENCY_MISSING`.
- A release that cannot be verified returns `RELEASE_RESOLUTION_REQUIRED`.
- Missing or invalid Atlassian authentication returns or reports
  `ATLASSIAN_AUTH_REQUIRED` with the selected client's remediation.
- Missing GitHub authentication is checked only for GitHub-dependent
  operations and returns or reports `GITHUB_AUTH_REQUIRED` with the supported
  login command.
- Missing routing returns `ROUTING_REQUIRED`; pending or unverifiable routing
  uses its existing fail-closed result.
- If a decision affects scope, ownership, routing, or external writes, the AI
  transfers the decision to the developer with the available options and does
  not continue until one exact option is confirmed.
- Non-interactive mode never opens a browser or chooses a default for missing
  context.

OAuth output is streamed directly from the selected client. Governance never
requests, parses, prints from storage, logs, or stores a developer API token,
OAuth credential, or OAuth state. Credentials remain owned by the client or OS
keyring.

## Repository activation

Bootstrap creates or updates only the managed governance entrypoints and lock
inside the selected application repository. The developer must:

1. review the exact managed-file diff;
2. commit it on a task branch;
3. open and merge the normal application-repository pull request;
4. start a fresh AI client session after merge;
5. run `beroka-governance doctor "$repo" --client <client>`; and
6. run operation-specific `preflight` immediately before external writes.

An existing registered repository keeps its pinned release. Bootstrap does not
silently upgrade it; the developer uses `beroka-governance update`.

## Documentation architecture activation

This release enforces the merged Backend Capability Registry, globally unique
Confluence Folder names, Integration Hub references, and Frontend Capability
Indexes for future governed work. Publication does not migrate or rewrite live
Confluence content. Missing exact Registry, Folder, content ID, or routing
causes the relevant operation to stop for developer input.

## Release preparation

The local release branch will:

- replace candidate/legacy wording with first-public-release wording;
- document official Backend and Frontend registration;
- keep `VERSION` at `v1.0.0`;
- document the interactive and non-interactive bootstrap commands;
- add a small release-readiness test for release identity, rollout scope, and
  the copy-paste bootstrap contract; and
- run the complete existing test suite in isolated HOME/XDG directories.

Before any push, report:

- the full developer installation and activation workflow;
- the local release branch and commit;
- all validation results;
- the exact local tag action that will occur after the release commit is on
  `main`; and
- confirmation that no remote tag or GitHub Release has been created.

## Publication gate

Publication happens only after the developer approves the pre-push report:

1. push the release branch and open a draft pull request;
2. merge the reviewed release PR;
3. fetch and verify the exact canonical `main` merge commit;
4. delete the unpublished local candidate tag;
5. create annotated `v1.0.0` at that exact commit;
6. verify tag type, target, tree cleanliness, tests, and remote absence;
7. push `v1.0.0` without force; and
8. create the GitHub Release from the verified tag.

If `v1.0.0` appears on the remote before step 7, stop with a release conflict;
never overwrite it.

## Acceptance criteria

- One documented interactive command onboards either a Backend or Frontend
  repository.
- The developer chooses when context is ambiguous.
- Automation requires exact repository, client, and version.
- Existing registrations are never silently upgraded.
- OAuth credentials remain outside governance.
- All bootstrap, connector, routing, documentation architecture, smoke, and
  release-readiness tests pass.
- No remote mutation occurs before the developer approves the pre-push report.
