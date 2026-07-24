# One-Command Bootstrap and Resumable Client Setup

## Goal

Reduce first-time Beroka Governance onboarding to one command while preserving
explicit client selection, pinned repository rules, client-owned OAuth, and
fail-closed external operations.

The official interactive command runs from the Git root to register:

```sh
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex
```

`codex` may be replaced by `claude` or `cursor`. Exactly one client is required
per invocation.

## Scope

V1.0.1 adds:

- a stable GitHub Release launcher asset;
- one-command installation for the current repository;
- reliable, bounded connector-health waiting;
- clear partial-success and resume behavior; and
- explicit repository, client, and execution-environment boundaries.

It does not:

- modify or replace the published `v1.0.0` tag;
- install Codex, Claude Code, Cursor, or OS packages;
- share OAuth credentials between clients or machines;
- silently update an existing repository lock;
- add a package-manager distribution channel; or
- change routing, integration-profile, or external-write policy.

Missing client or supporting commands remain `DEPENDENCY_MISSING` with a
specific dependency name.

## Release Launcher

Every stable release publishes `bootstrap.sh` as a GitHub Release asset.
`releases/latest/download/bootstrap.sh` therefore selects the latest stable
release without executing code from `main`.

The asset contains its release version and expected release commit. Before
executing package code, it must:

1. accept exactly one `--client codex|claude|cursor`;
2. resolve the current Git root and canonical GitHub origin;
3. clone the canonical governance repository at the asset's exact annotated
   tag into a temporary directory;
4. verify that the tag peels to the embedded commit; and
5. invoke the verified release's `beroka-governance bootstrap`.

Tag or commit mismatch returns `RELEASE_VERIFICATION_FAILED` before repository
or client configuration changes.

Interactive prompts read from `/dev/tty` so they remain usable when the
launcher itself arrives through standard input. Interactive mode without an
available terminal returns `TTY_REQUIRED` with the non-interactive command.
`--non-interactive` never opens `/dev/tty` or a browser; it uses the asset's
stable release and requires the client flag explicitly.

The launcher defaults only the stable release selection. It never guesses the
client or searches for a repository: the client is an explicit flag and the
execution location explicitly selects the current Git root.

## Installation Flow

The interactive flow is:

```text
current Git root
→ latest stable release launcher
→ tag and commit verification
→ governance package installation
→ selected-client repository registration
→ selected-client connector configuration
→ bounded connector-health check
→ confirmed client-owned OAuth when required
→ base and client-aware Doctor
→ phase summary
```

For a new registration, the latest stable release is shown before the user
confirms installation. For an existing registration, the repository's lock
remains authoritative; bootstrap must not upgrade it implicitly.

Installation and registration remain reusable even when connector
authentication is incomplete. Re-running the same launcher command resumes the
selected client's local setup without rewriting unchanged repository files.

## Repository, Client, and Environment Scope

Repository state is shared by the team:

- `.beroka-governance.lock` pins one governance release and lists enabled
  clients;
- `AGENTS.md` is the Codex entrypoint;
- `CLAUDE.md` is the Claude Code entrypoint; and
- `.cursor/rules/beroka-governance.mdc` is the Cursor entrypoint.

Adding a client is additive and uses canonical lock order
`codex,claude,cursor`. Every entrypoint loads the same pinned release and
central rules. Changing the model inside an already-enabled client requires no
governance setup.

Local state belongs to one client in one execution environment:

- governance CLI installation is per OS user/environment;
- connector configuration is per client/environment; and
- OAuth credentials remain owned by that client and its supported OS keyring
  or credential store.

A command launched in a VS Code Remote SSH terminal executes on the remote
host. The reviewed repository entrypoints travel with Git, but that remote host
still needs the CLI and connector authentication for the selected client.

Once a client entrypoint is reviewed and merged, another developer must not
re-add it. Bootstrap detects the existing entrypoint, produces no repository
diff, and performs only missing local setup.

## Connector Health

The current fixed three-second input hold is removed. Connector health uses a
response-driven wait with a total deadline of 15 seconds:

- stop as soon as the selected client's complete health record arrives;
- classify authentication only from client-provided evidence;
- retry safe read-only probing within the same deadline when a response is
  incomplete; and
- return `CONNECTOR_HEALTH_UNAVAILABLE` if the deadline expires without a
  classifiable record.

Unknown health must never be reported as successful or as authentication
required. The bounded wait applies only to connector-dependent setup, Doctor,
and preflight operations. Source-only governance operations do not probe
connectors.

## Results and Resume Behavior

Bootstrap reports completed phases before its final result:

```text
Release: PASS
Repository registration: PASS | NO_CHANGE
Client entrypoint: ADDED | ALREADY_CONFIGURED
Connector: PASS | AUTH_PENDING | HEALTH_UNAVAILABLE
```

Final behavior:

| Condition | Interactive result | Non-interactive result |
| --- | --- | --- |
| Connector healthy | `PASS`, exit 0 | `PASS`, exit 0 |
| Authentication required | Ask before invoking the client's OAuth flow | `ATLASSIAN_AUTH_REQUIRED`, exit nonzero |
| OAuth declined or incomplete | `AUTH_PENDING`, exit nonzero | Not applicable |
| Health remains unknown | `CONNECTOR_HEALTH_UNAVAILABLE`, exit nonzero | Same |

Every non-PASS result prints the exact command that resumes the selected client
on the current repository. Codex authentication remediation remains:

```text
codex mcp login atlassian
```

The client streams its OAuth URL, device code, or equivalent output directly
to the terminal. Governance does not parse, print independently, log, or store
OAuth state or credentials. It never accepts developer API tokens.

Repository registration is not rolled back for `AUTH_PENDING` or
`CONNECTOR_HEALTH_UNAVAILABLE`. External connector-dependent writes remain
blocked by their existing operation-specific preflight gates.

## Idempotency

Repeated launcher or bootstrap execution must be safe:

- the same client with current managed files produces no repository diff;
- a new client adds only its entrypoint and updates `CLIENTS`;
- existing clients and unrelated file content remain unchanged;
- healthy OAuth is reused without prompting or opening a browser; and
- missing, expired, or invalid OAuth invokes reauthentication only after
  interactive confirmation.

## Release Process

The V1.0.1 release process must:

1. merge the reviewed implementation to the canonical default branch;
2. run isolated package, connector, bootstrap, routing, and launcher tests;
3. create a new annotated `v1.0.1` tag at the verified merge commit;
4. publish `bootstrap.sh` as an asset of the `v1.0.1` GitHub Release; and
5. verify the `releases/latest/download/bootstrap.sh` URL resolves to that
   asset.

The published `v1.0.0` tag and release are immutable.

## Acceptance Tests

Tests use temporary Git repositories, HOME, XDG directories, client homes, and
fake client executables. They must not use real OAuth credentials or developer
API tokens. Fake clients control response readiness deterministically; tests do
not wait for real network deadlines.

Coverage must prove:

- the launcher rejects missing, duplicate, and invalid client selection;
- the launcher rejects execution outside a Git repository;
- interactive prompts work through `/dev/tty` when the script arrives by pipe;
- non-interactive mode never opens a browser or terminal prompt;
- tag or commit mismatch fails before local or repository writes;
- connector responses before, at, and after three seconds but within the
  deadline are classified correctly;
- missing responses return `CONNECTOR_HEALTH_UNAVAILABLE` at the deadline;
- missing, expired, and invalid OAuth return the required client remediation;
- successful OAuth is reused without another login;
- OAuth decline or failure preserves registration and returns `AUTH_PENDING`;
- rerunning the same client produces no repository diff;
- Codex, then Cursor, then Claude Code creates three independent entrypoints
  backed by one pinned release;
- an already-enabled client on another execution environment performs only
  local setup;
- base Doctor and source-only governance operations never probe OAuth; and
- the Backend, Frontend, and governance-repository pilots pass before release.
