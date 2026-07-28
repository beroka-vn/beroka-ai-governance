# Explicit Bootstrap Upgrade Design

**Date:** 2026-07-28
**Status:** Approved approach

## Problem

An existing repository pinned to `v1.0.1` cannot reach the schema-2 release
with the published commands:

- the `v1.0.1` CLI rejects schema 2 before `update` can install the new CLI;
- the new release launcher invokes `bootstrap`, which intentionally rejects a
  different existing pin; and
- uninstalling and reinstalling loses the safe in-place upgrade path expected
  by the team.

The MDL pilot reproduced this gap. It succeeded only when the unpublished new
CLI was invoked directly to update the repository.

## Goals

- Upgrade an existing same-major registration without uninstalling.
- Require an explicit operator decision; never silently upgrade.
- Preserve the repository identity, enabled clients, managed entrypoints, and
  client/OS-owned OAuth state.
- Give developers one compact command for install and the same command plus
  `--upgrade` for later releases.
- Reuse the verified release launcher, transactional `update`, additive
  registration, connector setup, and Doctor behavior.
- Keep first-time bootstrap behavior unchanged.

## Non-goals

- Automatic upgrades.
- Cross-major migration.
- Installing an AI client.
- Moving, deleting, or overwriting a published tag.
- Changing Jira, Confluence, or GitHub routing.

## CLI contract

The release launcher accepts one new flag:

```text
bootstrap.sh --client codex|claude|cursor [--upgrade] [--non-interactive]
```

First-time installation continues to omit `--upgrade`. An existing registered
repository uses:

```bash
sh bootstrap.sh --client codex --upgrade --non-interactive
```

Duplicate `--upgrade` flags or unknown arguments return usage error `2`.
`--upgrade` requires an existing valid registration. Same-version execution is
idempotent. A target older than the current pin returns `VERSION_MISMATCH`;
rollback remains the only supported downgrade path. The existing same-major
rule remains authoritative.

## README contract

The private release cannot be downloaded until GitHub CLI is installed.
Therefore the only workstation prerequisites are the selected AI client and
`gh`; GitHub authentication is reused when healthy and started through
client-owned browser OAuth only when missing.

The primary install command is:

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

Later same-major releases use the same command with one explicit flag:

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

Developers replace `codex` with `claude` or `cursor`. `pipefail` prevents a
failed download from appearing successful. The long cross-platform dependency
installer is removed from Quick start. After the verified asset is running,
interactive bootstrap offers to install missing `jq`; non-interactive
bootstrap fails closed with `DEPENDENCY_MISSING` and exact remediation. It
does not install the selected AI client.

## Execution flow

The launcher keeps its current trust boundary:

1. Resolve the current Git root and canonical GitHub remote.
2. Clone the embedded annotated release.
3. Verify tag type, peeled commit, and checked-out commit.
4. Only after verification, when `--upgrade` is present, invoke the verified
   new CLI:

   ```bash
   beroka-governance update "$repo" --to "$RELEASE_VERSION"
   ```

5. Invoke the existing verified bootstrap flow with the selected client,
   embedded version, and interaction mode.

The second bootstrap call preserves existing clients and adds the selected
client only when needed. It also prints the existing repository-review result,
configures only the selected connector, and runs Doctor.

## Failure behavior

- Without `--upgrade`, a mismatched existing pin still returns
  `VERSION_MISMATCH`.
- A missing or invalid registration stops during `update`; bootstrap and
  connector setup do not run.
- A failed update uses the existing transaction behavior and does not continue.
- Authentication failure after a successful update keeps the reviewed
  repository changes and returns the client-specific OAuth remediation.
- Non-interactive mode never opens a browser.
- No developer API token is accepted, printed, logged, or stored.

## Repository review

An upgrade changes the tracked lock and may change managed entrypoints. The
existing bootstrap summary must continue to report whether a repository PR is
required. Connector-only changes remain local and do not create an empty PR.

## Test strategy

1. Launcher parsing rejects duplicate `--upgrade`.
2. Without `--upgrade`, the launcher invokes only the existing bootstrap call.
3. With `--upgrade`, the verified new CLI receives `update` before `bootstrap`.
4. If `update` fails, bootstrap is not invoked.
5. `--upgrade` rejects a target older than the current pin.
6. Quick start reuses healthy GitHub authentication and starts `gh` browser
   OAuth only when authentication is missing.
7. Interactive bootstrap offers to install missing `jq`; non-interactive
   bootstrap returns `DEPENDENCY_MISSING`.
8. An isolated regression fixture starts with a schema-1 pinned repository and
   an old CLI that rejects schema 2, then proves the new verified launcher
   upgrades to the schema-2 release without uninstalling.
9. Existing launcher, bootstrap, connector, routing, and release suites remain
   green.
10. The MDL Codex pilot must repeat with the public-style upgrade command before
    publication.

## Release handling

The current local unpublished `v1.0.2` candidate tag points to the pre-fix
commit and must not be pushed. After this change is reviewed and merged, release
verification must confirm that the remote tag is still absent before replacing
only that local unpublished candidate with a new annotated `v1.0.2` at the
exact reviewed merge commit.
