# Opt-In Repository Governance Design

## Problem

Beroka installs managed instructions and Cursor hooks at user scope. Today an
unrelated Git repository therefore receives the same full instructions and
source-only standalone context as a cataloged repository. Cursor hooks can also
deny writes in that unrelated repository even though Beroka has no reviewed
authority over it.

Governance must instead activate only for an exact canonical GitHub repository
identity present in the pinned release's Central catalog. Absence from the
catalog means outside the governance boundary, not partially governed.

## Goals

- Make exact active-release catalog membership the only activation signal.
- Return a compact `NOT_GOVERNED` result for an unregistered repository.
- Load no runtime entrypoint, general rules, profile, or integration rules for
  an unregistered repository.
- Pass Cursor hooks through without role, receipt, connector, template, Jira,
  Confluence, or GitHub governance checks when no workspace repository is
  registered.
- Preserve all existing fail-closed behavior for registered repositories and
  malformed catalog records.
- Preserve registered standalone, Backend, Frontend, and integration outcomes.
- Reduce Codex, Claude, and Cursor global managed instructions to a repository
  boundary sentinel.
- Keep registration a reviewed governance release change.

## Non-goals

- Adding a local `register` command.
- Writing governance files into an application repository.
- Inferring registration from paths, folder names, workspace proximity, or a
  different open repository.
- Weakening routing, role, OAuth, connector, handoff, or external-write gates
  for a registered repository.
- Automatically creating Jira or Confluence routing for a new repository.

## Chosen Approach

Use the existing canonical remote and catalog lookup as the single activation
boundary. `resolve_repository_context` sets `ROUTING_ACTIVE` only after an
exact catalog record parses successfully. If no exact record exists, it sets
`NOT_GOVERNED` and no synthetic standalone profile or routing values.

This keeps one classifier for context, preflight, and hooks. A separate probe
command would duplicate repository resolution, while project-local enrollment
would contradict the user-scoped package and mutate application repositories.

## Repository State Contract

Repository classification has two successful states:

- `ROUTING_ACTIVE`: an exact record exists in the pinned release and passes all
  current catalog validation.
- `NOT_GOVERNED`: the canonical GitHub slug is valid but has no exact record in
  the pinned release.

An existing but malformed record remains an error. Invalid Git repositories,
ambiguous remotes, non-GitHub canonical remotes, release-integrity failures,
and role mismatches for registered records retain their current fail-closed
results. `NOT_GOVERNED` must never hide a broken record.

## Context Contract

For `ROUTING_ACTIVE`, `beroka-governance context REPO` preserves the current
full output and loads:

1. `runtime/entrypoint.md`
2. repository and release identity
3. `runtime/rules/general.md`
4. the selected profile
5. work-item and integration rules when selected

For `NOT_GOVERNED`, context exits successfully and prints exactly two short
lines:

```text
Result: NOT_GOVERNED
Repository: owner/repository
```

It does not print version, routing, profile, dependency, write, or rule text.
The result stays below the issue's three-line ceiling.

## Managed Entrypoint Contract

The Codex `AGENTS.md`, Claude `CLAUDE.md`, and Cursor User Rule managed blocks
contain only the boundary behavior:

- in a Git repository, run `beroka-governance context "$PWD"` before planning,
  implementation, Jira, GitHub, or Confluence work;
- apply the returned rules only when context does not return
  `Result: NOT_GOVERNED`;
- rerun after compaction/session resume and repository or workspace changes.

Client-specific workflow, OAuth, Jira, Confluence, and handoff policy remains
in the registered runtime context or command remediation instead of every
global prompt. Managed markers and preservation of personal text remain
unchanged. Each managed entrypoint is limited to 1,024 bytes and 140 words.

## Preflight Contract

Preflight resolves the active release and exact repository before client,
instruction, role, routing, connector, authentication, capability, or template
checks. For `NOT_GOVERNED`, it exits successfully with:

```text
Result: NOT_GOVERNED
Repository: owner/repository
```

For `ROUTING_ACTIVE`, the existing operation-specific preflight path is
unchanged. A caller must treat `NOT_GOVERNED` as governance not applying, not
as a Beroka authorization decision.

## Cursor Hook Contract

Hooks classify all valid Git workspace roots against the pinned catalog before
governed enforcement:

| Workspace state | Hook behavior |
| --- | --- |
| One registered repository | Existing governed behavior |
| Exact registered Backend+Frontend pair | Existing FULL_STACK behavior |
| No registered repositories | Pass through immediately |
| Registered repository plus an unknown or invalid multi-root shape | Existing fail-closed behavior |
| Registered catalog record is malformed | Fail closed |

For an unregistered workspace:

- `sessionStart` adds only the compact `NOT_GOVERNED` context and writes no
  governed receipt;
- `beforeSubmitPrompt` and `preCompact` return an empty success object;
- `beforeMCPExecution` and `beforeShellExecution` return
  `{ "permission": "allow" }` before provider, receipt, link, template,
  connector, Jira, Confluence, or GitHub checks.

The multi-root classifier may pass through only when every resolved Git root is
uncataloged. One registered root keeps the current strict workspace resolver,
so an unrelated folder cannot disable governance for a registered repository.

## Repository Registration

Registration is not performed from the application repository. An authorized
change in this governance repository must:

1. add `runtime/repositories/<owner>/<repository>.conf` using the exact
   canonical GitHub slug;
2. provide reviewed `SCHEMA_VERSION`, profile, Jira, Confluence, integration,
   and cross-repository routing values;
3. update an integration inventory only when the selected integration profile
   requires it;
4. pass catalog, routing, client, and release validation;
5. merge through review and ship in a new immutable governance release.

Users then upgrade their user-scoped installation to that release. Any clone or
worktree whose canonical remote normalizes to the exact catalog slug becomes
governed. A local path, matching folder name, or unshipped catalog PR does not.

## Tests

Existing shell tests will provide the regression coverage:

- `tests/smoke.sh`: compact unknown context, no full rules, malformed record
  failure, and unchanged registered standalone behavior.
- `tests/routing.sh`: registered Backend, Frontend, standalone, integration,
  canonical clone/worktree, and active-release-only registration.
- `tests/cursor-hooks.sh`: all hook events pass through for single and
  multi-root unregistered workspaces; mixed registered/unregistered shapes
  remain fail-closed; registered fixtures retain current outcomes.
- `tests/bootstrap.sh` and `tests/documentation-architecture.sh`: all three
  installed entrypoints remain minimal, preserve personal text, and obey an
  explicit byte ceiling.
- `tests/release.sh`: release contents and catalog validation remain intact.

Tests assert behavior, exit status, connector-call absence, rule-text absence,
line count, word count, and byte count. The compact context is limited to 160
bytes and eight words; each managed entrypoint uses the limits above. No new
test framework or dependency is needed.

## Rollout and Compatibility

The change ships only in a new reviewed governance release. Existing users
remain on their pinned behavior until they upgrade. Once upgraded, cataloged
repositories retain enforcement and unregistered repositories immediately
leave the governance boundary. No application repository migration is needed.

PR #83 is stacked on PR #82 so the trusted actual-body and cross-team isolation
gates remain in the registered path unchanged.
