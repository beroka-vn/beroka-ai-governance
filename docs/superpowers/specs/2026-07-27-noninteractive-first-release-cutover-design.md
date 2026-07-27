# Non-Interactive First Release Cutover

**Date:** 2026-07-27  
**Target release:** `v1.0.1`

## Context

`v1.0.0` was published before team rollout, has no Release assets, and has no
known team consumers. The first supported team deployment will use `v1.0.1`
through the GitHub `latest` Release asset.

The team-facing onboarding command is:

```sh
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive
```

## Decisions

1. Keep `VERSION=v1.0.1`; do not reuse the previously published `v1.0.0`
   version for a different commit.
2. Make the non-interactive command the only Quick Start and deployment
   command in active user documentation.
3. Retain interactive CLI capability for explicit OAuth login and recovery.
   Removing an onboarding example does not remove supported client OAuth
   flows.
4. Keep historical specifications, plans, and Git commits for traceability.
   They may describe the earlier `v1.0.0` work but are not current operating
   instructions.
5. Remove the GitHub Release and tag `v1.0.0` only after `v1.0.1` is published
   and its public launcher passes a clean-machine simulation.
6. Do not rewrite Git history and do not force-push any ref.

## User-visible behavior

The deployment command never opens a browser. On a machine where the selected
client already has valid Atlassian OAuth, bootstrap ends with exactly one
`Result: PASS`.

When OAuth is missing or invalid, repository installation and registration
remain in place, bootstrap exits nonzero with exactly:

```text
Result: ATLASSIAN_AUTH_REQUIRED
Remediation: codex mcp login atlassian
```

The developer runs the client-owned remediation command and then reruns the
same non-interactive deployment command. Governance never requests, prints,
logs, or stores a developer API token or OAuth credentials.

Other clients remain explicit:

```text
--client claude
--client cursor
```

One invocation still selects exactly one client. Setup remains local to each
execution environment while all clients load the same repository-pinned
governance release.

## Documentation boundary

Active documentation consists of `README.md`, `handbook.md`, and
`PACKAGE-DESIGN.md`.

- `README.md` presents the non-interactive launcher first and does not present
  the interactive launcher pipeline.
- `handbook.md` uses the same command for team rollout and documents the
  fail-closed OAuth remediation/rerun sequence.
- `PACKAGE-DESIGN.md` defines the non-interactive launcher as the supported
  deployment path while retaining the interactive capability contract.
- Active documentation no longer calls `v1.0.0` the current or first stable
  team release.
- Historical files under `docs/superpowers/specs/` and
  `docs/superpowers/plans/` are not rewritten.

## Release sequence

1. Merge a reviewed follow-up PR containing the documentation and release-test
   changes.
2. Delete the unpushed local `v1.0.1` candidate tag and discard the old
   temporary asset.
3. Create a new annotated local `v1.0.1` tag at the follow-up merge commit.
4. Build `bootstrap.sh` with that exact version and commit embedded.
5. Run isolated non-interactive pilots for Backend, Frontend, and Governance.
6. Push `v1.0.1` without force and publish it as the latest stable GitHub
   Release with the verified `bootstrap.sh` asset.
7. Run the public command from a fresh canonical HTTPS clone and isolated
   HOME/XDG/CODEX_HOME. Accept only `PASS` or the exact fail-closed Atlassian
   remediation.
8. Record the existing `v1.0.0` tag object, peeled commit, and Release metadata.
9. Delete the GitHub Release `v1.0.0`, delete remote
   `refs/tags/v1.0.0` without force, and delete the local tag.
10. Verify that `v1.0.1` remains the latest stable Release, its asset embeds the
    merge commit, and the remote no longer contains `v1.0.0`.

Publication or public-simulation failure stops the sequence before deletion of
`v1.0.0`.

## Test and acceptance gates

- Release tests require the exact non-interactive pipeline as the first Quick
  Start command and reject the interactive pipeline from active onboarding.
- Active-documentation tests reject claims that `v1.0.0` is the current stable
  team release.
- Existing isolated connector, bootstrap, launcher, routing, and documentation
  suites remain green.
- Each canonical pilot leaves only the selected client's managed entrypoint
  and lock file, pins `v1.0.1` to the exact merge commit, and returns one final
  result.
- Before deletion, GitHub reports a published stable `v1.0.1` with the expected
  asset and commit.
- After deletion, both `gh release view v1.0.0` and remote tag lookup for
  `v1.0.0` report absence.
