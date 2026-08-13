# Additive Client Enrollment README Design

**Date:** 2026-08-13
**Status:** Approved and implemented

## Goal

Make the README shorter and show the exact supported way to add another AI
client to an existing Beroka governance installation without removing clients
that are already enrolled.

## Scope

- Document additive enrollment with a concrete Codex-to-Claude example.
- Keep the existing bootstrap command as the only public enrollment path.
- Remove repeated operational explanations and obsolete release-history detail
  from the README.
- Keep detailed connector, authentication, downgrade, uninstall, and release
  guidance in `handbook.md` and `PACKAGE-DESIGN.md`.
- Update documentation assertions so the concise README remains protected by
  tests.

This change does not alter runtime behavior, client state formats, connector
configuration, release version, tags, or GitHub releases.

## User Experience

The README will explain that enrollment is additive. A user who installed
governance for Codex can add Claude by running the current release launcher
again with `--client claude` and without `--upgrade`:

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client claude
'
```

After this command, both Codex and Claude remain enrolled. Bootstrap installs
or refreshes only Claude's managed instruction block and connector setup while
preserving the healthy Codex setup. The same pattern applies to any supported
second client: `codex`, `claude`, or `cursor`.

`--upgrade` remains reserved for changing the active governance release. It is
not needed when adding a client to the current release.

## README Structure

The README remains the concise entry point:

1. **Quick start** — one canonical installation command and a short statement
   of supported clients.
2. **Add another client** — the Codex-to-Claude example, additive semantics,
   and the distinction from `--upgrade`.
3. **Operate governance** — compact context and preflight examples with links
   to the handbook for connector and OAuth detail.
4. **Upgrade, downgrade, uninstall, and CI** — retain the commands users need,
   remove repeated prose, and link to the handbook for edge cases.
5. **Team workflow and source of truth** — preserve the existing high-level
   collaboration contract and document index.

The long `v1.0.11` feature history and repeated explanations of OAuth output,
Cursor internals, catalog routing, and upgrade semantics will be removed from
the README where the handbook or package design already owns that detail.

## Runtime and Data Flow

No runtime change is required. Existing behavior already provides the desired
flow:

1. Bootstrap loads the current comma-separated client enrollment.
2. `canonical_clients` merges the selected client in canonical order.
3. `enable_client` atomically writes the merged enrollment.
4. Bootstrap installs instructions and configures connectors only for the
   selected client unless a release upgrade requires refreshing all enabled
   instructions.

Existing bootstrap coverage already verifies that adding Claude after Codex
produces `codex,claude`, preserves Codex instructions, and invokes only the
Claude connector path.

## Testing

- Add or update documentation assertions for the `Add another client` heading,
  the `--client claude` example, the preservation statement, and the rule that
  adding a client does not use `--upgrade`.
- Remove assertions that require obsolete version-specific README sections or
  duplicated prose.
- Run `sh tests/documentation-architecture.sh` and `sh tests/release.sh` during
  the red-green cycle.
- Run the complete `tests/*.sh` suite before opening the documentation PR.

## Release Boundary

This documentation change will be prepared on its own reviewed branch and pull
request. It must not bump `VERSION`, create `v1.0.12`, tag a commit, publish a
GitHub release, or merge itself.

Regression [#67](https://github.com/beroka-vn/beroka-ai-governance/issues/67)
is a separate P0 runtime change and must use its own branch, tests, and pull
request. A separately authorized `v1.0.12` release can be prepared only after
both the documentation change and the #67 fix are merged and the combined
`main` branch passes the release gate.
