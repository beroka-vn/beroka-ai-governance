# Modular Governance CLI Design

**Status:** Approved in chat

**Date:** 2026-08-27

## Goal

Restructure Beroka AI Governance so its source is easier to maintain and extend
without changing the public CLI, bootstrap flow, release package, output, or
runtime dependencies.

The immediate work creates a modular POSIX shell source tree and a deterministic
build that still publishes one self-contained `bin/beroka-governance`
executable. It does not implement workforce offboarding, repository deletion,
AI usage collection, telemetry storage, or a plugin framework.

## Constraints

- Preserve all commands, arguments, exit statuses, result codes, and output.
- Preserve the verified, immutable release and user-scoped installation model.
- Preserve `release/bootstrap.sh.in` as a small, independent release launcher.
- Continue to support POSIX `sh` on Linux and macOS.
- Add no runtime dependency.
- Keep the generated CLI committed so release packaging remains unchanged.
- Keep security and destructive-action boundaries at least as strict as today.

## Selected Approach

Split the monolithic CLI into domain-oriented source modules and concatenate
them in a fixed order at build time. The generated artifact remains the only
runtime entrypoint.

Runtime sourcing was rejected because it makes installation integrity and path
resolution more fragile. A language rewrite was rejected because it adds
migration risk and dependencies without being required for the current goal.

## Source Layout

```text
src/
├── 00-runtime.sh
├── 10-repository.sh
├── 20-release.sh
├── 30-clients.sh
├── 40-governance.sh
├── 50-cursor-hooks.sh
└── 90-main.sh

scripts/build-cli.sh
bin/beroka-governance
release/bootstrap.sh.in
```

The modules own these responsibilities:

- `00-runtime.sh`: constants, error handling, path safety, JSON and shared
  low-level helpers.
- `10-repository.sh`: canonical repository discovery, catalog parsing,
  routing, repository state, and role scope.
- `20-release.sh`: release verification, installation, upgrade, user-state
  transactions, and instruction installation.
- `30-clients.sh`: Codex, Claude, Cursor and GitHub client adapters,
  connector configuration, health checks, and OAuth boundaries.
- `40-governance.sh`: context, preflight, Jira and Confluence policies,
  handoff validation, and governance commands.
- `50-cursor-hooks.sh`: workspace classification, receipts, hook parsing,
  enforcement, and Cursor hook commands.
- `90-main.sh`: usage text and the single command dispatcher.

These are broad ownership boundaries, not a request to create one file per
function. A function belongs to the module that owns its policy or external
boundary. Shared low-level helpers remain in runtime only when at least two
domains use them.

## Dependency Direction

```text
main → commands and hooks → governance policies
                          → client adapters
                          → repository and release
                          → runtime helpers
```

Dependencies flow downward. Runtime and repository modules must not dispatch
commands or call Cursor hooks. The main module contains the only top-level
argument dispatcher.

The first extraction preserves necessary shell globals and existing function
names. Each module documents the important state it owns or mutates. Reducing
shared state happens only in later, behavior-protected changes; the foundation
must not become a hidden rewrite.

## Build Contract

`scripts/build-cli.sh` reads an explicit, fixed module manifest, concatenates
the modules into a temporary file, validates it with `sh -n`, marks it
executable, and atomically replaces `bin/beroka-governance`.

The script supports:

- default mode: regenerate the committed artifact;
- `--check`: generate to a temporary location and fail when it differs from
  the committed artifact.

The output must be byte-deterministic on Linux and macOS. The source modules
contain the complete script in build order; the build adds no timestamps,
hostnames, absolute paths, or environment-derived content.

## Migration

Work is delivered in small reviewable pull requests:

1. **Build foundation:** introduce the source tree, deterministic build,
   generated-artifact check, and mechanically extract the current CLI without
   changing behavior.
2. **Boundary cleanup:** document module state ownership and reduce verified
   cross-module coupling in release/catalog code.
3. **Client boundary cleanup:** isolate client and connector adapters while
   retaining current provider behavior.
4. **Cursor boundary cleanup:** isolate hook parsing and enforcement behind its
   existing command contract.

The first pull request is sufficient to establish the scalable source layout.
Later cleanup pull requests must be justified by concrete coupling encountered
in the extracted modules; speculative abstractions are out of scope.

## Validation

The build foundation adds a test that proves:

- `--check` passes for the committed generated artifact;
- changing a source module without rebuilding makes `--check` fail;
- two builds from identical source have the same checksum;
- malformed generated shell is rejected before replacing the artifact.

All existing suites continue to execute the generated
`bin/beroka-governance`. The release gate remains syntax validation plus the
complete shell test suite on Ubuntu and macOS.

Public behavior is protected by the current tests. Any extraction that requires
changing an expected public result is not part of this refactor.

## Future Domain Boundaries

### Workforce offboarding

Offboarding is a privileged workflow, separate from bootstrap:

```text
discover inventory → create immutable plan → human approval → execute → audit
```

No direct “delete everything” command is allowed. Every repository, permission,
or resource must be enumerated in the reviewed plan. Execution must bind human
confirmation to the exact plan identity and current inventory, and must retain
an auditable result. Destructive operations remain unavailable until that
feature receives its own design and authorization model.

### AI usage management

Usage collection is a runtime subsystem, not installation logic. Client
adapters may emit a normalized event containing:

```text
user, client, model, input_tokens, output_tokens, timestamp, scope
```

Collection must use provider-reported counts rather than prompt-length
estimates. It must not collect prompt or response content, OAuth URLs, API keys,
or credentials. Retention, user visibility, consent, storage, and reporting
require a separate design.

If either future domain outgrows POSIX shell, it may become a separate service
or binary behind a stable CLI contract. This design does not create that
contract before a real consumer exists.

## Security and Release Invariants

- Bootstrap installs and activates verified releases; it does not run business
  workflows or telemetry collection.
- Generated artifacts remain covered by release integrity checks.
- No module stores credentials.
- External-write preflight and role enforcement remain unchanged.
- Offboarding cannot reuse ordinary bootstrap or installation authority.
- Usage collection is opt-in and cannot activate governance for an
  unregistered repository.

## Success Criteria

- Maintainers can locate code by domain without reading a single 6,000-line
  source file.
- Release consumers still receive one self-contained executable.
- Existing behavior and test output remain unchanged.
- CI detects stale or nondeterministic generated artifacts.
- New domains have an explicit place to integrate without entering bootstrap.
