# Codex Delayed Reauthentication Classification Design

**Date:** 2026-08-13
**Issue:** [#67](https://github.com/beroka-vn/beroka-ai-governance/issues/67)
**Status:** Approved

## Goal

Restore automatic producer-owned Atlassian reauthentication when Codex reports
an OAuth-labeled empty tool inventory before its definitive reauthentication
evidence becomes visible.

## Root Cause

The Codex health probe currently treats any structurally valid Atlassian record
with `authStatus: oAuth` as complete. When Codex first emits that record with an
empty `tools` object, governance stops the app server immediately. A delayed
`reauthenticationRequired` notification or refresh-failure diagnostic therefore
never reaches the shared authentication classifier. Preflight sees a complete
empty inventory and incorrectly returns `CONNECTOR_CAPABILITY_REQUIRED`.

The managed instructions and interactive preflight handoff are still correct:
they automatically run `codex mcp login atlassian` when preflight returns the
authentication-required boundary. The regression occurs before that boundary
is selected.

## Design

An OAuth-labeled empty Atlassian inventory requires two observations before it
is accepted as an authenticated capability result.

1. On the first valid empty `oAuth` response, keep the existing app-server
   process alive and issue one more `mcpServerStatus/list` request.
2. Continue checking all accumulated output with the existing structured
   reauthentication and HTTP-auth classifiers.
3. If authentication evidence appears, classify health as authentication
   required before capability resolution.
4. If a second valid response is still an empty `oAuth` inventory with no
   authentication evidence, accept it as genuinely authenticated and allow
   capability resolution to return `CONNECTOR_CAPABILITY_REQUIRED`.
5. Preserve the existing bounded probe deadline and malformed-response handling.

This uses the existing probe protocol and classifiers. It does not add a
Codex-version-specific log parser, infer authentication failure solely from an
empty inventory, or persist producer output.

## Interactive Flow

After delayed evidence is classified as authentication required, the existing
preflight flow remains authoritative:

1. Non-interactive preflight returns `ATLASSIAN_AUTH_REQUIRED` with
   `Remediation: codex mcp login atlassian` and does not invoke login.
2. Interactive preflight runs exactly `codex mcp login atlassian` without an
   extra user confirmation.
3. Producer output is streamed unchanged and is never parsed, copied, logged,
   or persisted by governance.
4. After login succeeds, preflight performs a fresh health and capability probe.
5. The write may continue only after `Result: PASS`.

Doctor and Cursor hooks remain non-interactive and do not start login.

## Tests

Extend the existing fake Codex app server in `tests/routing.sh` with a delayed
reauthentication fixture:

- The first status request returns the exact observed state: a valid Atlassian
  record with `authStatus: oAuth` and an empty `tools` object.
- The next observation exposes `reauthenticationRequired` and the empty record.
- A non-interactive Jira-write preflight must return
  `ATLASSIAN_AUTH_REQUIRED`, must not return `CONNECTOR_CAPABILITY_REQUIRED`,
  and must not invoke login.
- An interactive Jira-write preflight must invoke login exactly once, preserve
  opaque producer output, rerun the probe, and return `PASS` after the fake
  producer becomes healthy.

Retain the existing authenticated-empty-inventory case and assert that it still
returns `UNSUPPORTED / RUNTIME_INVENTORY / CONNECTOR_CAPABILITY_REQUIRED`.

Run the complete local `tests/*.sh` suite and require both GitHub Actions matrix
jobs (`ubuntu-latest` and `macos-latest`) to pass before completion.

## Scope Boundaries

- Change only the shared Codex probe completion logic and its closest regression
  coverage, plus this issue's spec and plan.
- Do not change client enrollment, README cleanup, compatibility inventories,
  managed instruction wording, `VERSION`, tags, or releases.
- Do not merge the pull request or prepare `v1.0.12` without the user's later
  explicit authorization.
