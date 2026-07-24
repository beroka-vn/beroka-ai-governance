# Client-Specific Governance Entrypoints

## Goal

Register only the AI client selected for an invocation while allowing a
repository to add Codex, Claude Code, and Cursor explicitly over time. Every
enabled client must load the same pinned Beroka Governance release and central
ruleset.

## Decision

The repository lock is the source of truth for enabled clients. Client
selection is additive and idempotent:

- an invocation selects exactly one of `codex`, `claude`, or `cursor`;
- selecting a new client adds only that client's entrypoint;
- selecting an enabled client does not rewrite unchanged repository files;
- adding a client never removes another enabled client; and
- governance never enables every installed client automatically.

File presence alone is not sufficient state because it cannot distinguish an
unconfigured client from a deleted entrypoint. A separate client registry file
would duplicate the lock, so the lock owns this state.

## Repository Contract

Every registered repository contains `.beroka-governance.lock`. Its allowlisted
schema becomes:

```text
SOURCE=beroka-vn/beroka-ai-governance
REPOSITORY=beroka-vn/example-backend
VERSION=v1.0.0
COMMIT=0123456789abcdef0123456789abcdef01234567
CLIENTS=codex,claude
```

`CLIENTS` must:

- contain at least one client;
- contain only `codex`, `claude`, and `cursor`;
- contain no duplicates; and
- use canonical order: `codex,claude,cursor`.

The CLI continues to parse the lock as data and must never source, evaluate, or
execute it.

Each enabled client owns one repository entrypoint:

| Client | Managed entrypoint |
| --- | --- |
| Codex | managed block in `AGENTS.md` |
| Claude Code | managed block in `CLAUDE.md` |
| Cursor | `.cursor/rules/beroka-governance.mdc` |

Each entrypoint independently directs its client to
`beroka-governance context "$PWD"`. Claude Code and Cursor must not depend on
`AGENTS.md`; therefore selecting either client does not create `AGENTS.md`.
Entrypoints contain routing instructions only. The validated release referenced
by the lock remains the single source for governance rules and templates.

Unrelated pre-existing content in `AGENTS.md` and `CLAUDE.md` remains preserved.
An unlisted client must not have a Beroka-managed block or dedicated Cursor
rule. Such stale managed content is `ENTRYPOINT_DRIFT`.

Unpublished candidate locks without `CLIENTS` are invalid and must be recreated
with bootstrap. There is no migration requirement before the first public
`v1.0.0` release.

## CLI Behavior

### Register

Direct registration requires explicit client selection:

```text
beroka-governance register REPO --version VERSION --client codex|claude|cursor [--dry-run]
```

First registration writes the lock and only the selected entrypoint. Repeating
the same command is idempotent. Registering another client with the same pinned
version adds that client to `CLIENTS` and writes only its entrypoint.

Changing versions remains the responsibility of `update` or `rollback`;
register must reject a version different from the existing lock.

### Bootstrap

Bootstrap already selects exactly one client explicitly or through the approved
interactive detection flow. It passes that client to registration:

```text
beroka-governance bootstrap REPO --client codex
```

For an enabled client, bootstrap produces no repository diff when managed
content is current. For a new client, it adds only that client to the lock and
creates only its entrypoint.

Repository registration and local connector readiness are separate:

- `CLIENTS` and entrypoints are reviewed repository state shared by the team;
- dependencies, connector configuration, OAuth state, and credentials remain
  local to each developer's selected client and OS keyring.

Bootstrap checks the selected client's local connector health. Healthy
authentication is reused without starting OAuth. A new machine may need local
connector setup even when the repository already enables that client.

### Doctor and Context

Base `doctor` and `context` validate:

- the lock and pinned release;
- every entrypoint listed in `CLIENTS`; and
- the absence of stale Beroka-managed entrypoints for unlisted clients.

A missing, modified, unsafe, or stale managed entrypoint returns
`ENTRYPOINT_DRIFT`. A newly selected entrypoint hidden by Git ignore rules
returns `WORKTREE_CONFLICT`.

`doctor REPO --client CLIENT` first requires the client to be listed in
`CLIENTS`. If it is not listed, it returns:

```text
Result: CLIENT_SETUP_REQUIRED
Remediation: beroka-governance bootstrap REPO --client CLIENT
```

It then applies the existing dependency, connector, capability, and
authentication checks only to that selected client.

### Update, Rollback, and Unregister

`update` and `rollback` preserve `CLIENTS` and refresh only the entrypoints
declared there. They must not create undeclared client files.

`unregister` removes the lock and all Beroka-managed entrypoints declared by the
lock while preserving unrelated content. Stale undeclared managed content must
be resolved before unregister continues.

## Transaction and Failure Rules

Lock and entrypoint changes remain one repository transaction. Adding a new
client must fail atomically if its target is ignored, dirty, unsafe, or cannot
be written. No lock update or other client entrypoint change may remain after a
failed operation.

Connector setup and OAuth remain outside the repository transaction because
they are client-owned local state. Governance must never accept, print, log, or
store developer API tokens, OAuth credentials, device codes, or OAuth state.

## Tests

Tests use temporary repositories, HOME, XDG, client homes, and fake clients with
no real credentials. They must prove:

- Codex registration creates only the lock and `AGENTS.md`;
- Claude registration creates only the lock and `CLAUDE.md`;
- Cursor registration creates only the lock and its dedicated rule;
- adding clients accumulates canonical `CLIENTS` state without changing existing
  entrypoints;
- repeating setup for an enabled client produces no repository diff;
- all enabled clients resolve the same pinned release and ruleset;
- an ignored entrypoint fails atomically without changing the lock;
- deleted or modified enabled entrypoints produce `ENTRYPOINT_DRIFT`;
- stale managed content for an unlisted client produces `ENTRYPOINT_DRIFT`;
- `doctor --client` returns `CLIENT_SETUP_REQUIRED` for an unlisted client;
- update and rollback preserve the enabled-client set;
- unregister preserves unrelated `AGENTS.md` and `CLAUDE.md` content; and
- healthy local authentication is reused without invoking OAuth.

The canonical Frontend pilot with `--client codex` must not create or require a
`.cursor` path. Backend and Frontend pilots must pass before publishing the
first `v1.0.0` tag.
