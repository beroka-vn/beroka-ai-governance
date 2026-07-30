# Cursor First-Run Global MCP Design

Status: Review requested

**Issue:** #30  
**Target release:** `v1.0.4`

## Problem

New Cursor users can install `cursor-agent` and the verified governance
release, but first connector setup may end with:

```text
Provider: atlassian
Connector: HEALTH_UNAVAILABLE
Resume: beroka-governance setup-connectors --client cursor
Result: CONNECTOR_HEALTH_UNAVAILABLE
```

Governance already writes the reviewed Atlassian URL to
`~/.cursor/mcp.json`. It then probes Cursor Agent immediately. A first-run
Cursor installation may return no classifiable `atlassian: ready/auth...`
record, so governance fails unknown health before it invokes
`cursor-agent mcp login atlassian`. The developer therefore receives neither
the OAuth URL nor the opportunity to authenticate.

This is the unresolved first-run path related to #23, not a missing
`cursor-agent` dependency and not the release-manifest bug in #27.

## Scope selection

Beroka governance is installed in user scope and can govern more than one
reviewed repository. Its Atlassian connector is therefore global:

```text
~/.cursor/mcp.json
```

A project connector at `<current-repository>/.cursor/mcp.json` may serve that
project, but it cannot satisfy user-scope governance. Setup inspects only the
global file and the current repository file. It never scans the workstation
for other repositories.

Project configuration is read only to provide an accurate message. It is never
edited, copied, deleted, or accepted as the global connector.

## First-run flow

Cursor connector setup preserves the existing three global states:

1. A compatible global Atlassian connector exists: probe it normally.
2. A conflicting global `atlassian` connector exists: fail closed with
   `CONNECTOR_MISSING`.
3. No global Atlassian connector exists: enter the new first-run path.

In the first-run path:

1. Report whether the current repository has a project-only Atlassian
   connector. When present, report `Project MCP: PRESENT_IGNORED`.
2. Interactive setup asks one question:
   `Install global Atlassian MCP and start OAuth now? [y/N]`.
3. Declining leaves global and project configuration unchanged and returns
   `ATLASSIAN_AUTH_REQUIRED` with
   `beroka-governance setup-connectors --client cursor` remediation because
   Cursor cannot log in before the global server entry exists.
4. Accepting merges the reviewed URL into `~/.cursor/mcp.json` with the
   existing safe user-file transaction, preserving unrelated JSON.
5. Because governance created this exact connector, it invokes
   `cursor-agent mcp login atlassian` immediately instead of requiring a
   pre-login health classification.
6. Provider output remains attached to the terminal. The browser URL is
   displayed or opened by Cursor Agent and is not parsed, copied, logged, or
   stored by governance.
7. After the login command returns, governance clears its probe cache and runs
   the normal health check.

The public installation command remains one command. The release launcher
already attaches interactive package setup to `/dev/tty`, so the confirmation
and provider OAuth output remain visible even though `bootstrap.sh` is
downloaded through a pipe.

## Existing connector flow

An existing compatible global connector remains idempotent:

- healthy returns `PASS` without another prompt or login;
- a classifiable authentication-required state uses the existing OAuth prompt;
- unknown or failed health remains `CONNECTOR_HEALTH_UNAVAILABLE`.

Only the connector created during the current invocation bypasses the initial
health classification. Unknown health for an existing connector must not be
silently treated as an authentication problem because it may represent a
network, client, or provider failure.

Cursor MCP inspection and login continue to run from `/` while preserving the
user's `HOME` and credentials. This prevents the current repository's
`.cursor/mcp.json` from shadowing or duplicating the global connector.

## Non-interactive behavior

Non-interactive setup never opens a browser or mutates a missing global Cursor
connector. It reports any project-only connector as insufficient, then returns:

```text
Result: ATLASSIAN_AUTH_REQUIRED
Remediation: beroka-governance setup-connectors --client cursor
```

The interactive resume command performs the single global-install and OAuth
confirmation. Existing compatible global state retains the current
non-interactive health behavior.

## Failure behavior

- Invalid global JSON: `GOVERNANCE_NOT_READY`.
- Conflicting global Atlassian URL: `CONNECTOR_MISSING`.
- Missing global connector with declined or unavailable interaction:
  `ATLASSIAN_AUTH_REQUIRED`.
- Cursor login command fails or authentication remains incomplete:
  `AUTH_PENDING` with the existing resume command.
- Post-login unclassifiable health: `CONNECTOR_HEALTH_UNAVAILABLE`.
- Healthy post-login state: connector and authentication `PASS`.

Every failure preserves project configuration. A failure before the global
file transaction leaves global configuration unchanged; a completed global
configuration is retained so the documented resume command can continue OAuth.

## Verification

The connector integration fixture will reproduce a newly created global
connector whose first `cursor-agent mcp list` result is unknown. Against the
current code it must fail before login with
`CONNECTOR_HEALTH_UNAVAILABLE`.

After the fix, tests must prove:

1. First-run interactive setup asks once, creates the global connector, invokes
   `cursor-agent mcp login atlassian`, exposes its OAuth URL, and then passes
   health.
2. Cursor MCP commands run from `/`.
3. Unrelated global JSON is preserved.
4. Project-only JSON is reported and remains byte-for-byte unchanged.
5. Non-interactive first-run neither writes global config nor calls login.
6. Declining first-run leaves global config absent.
7. Existing healthy global setup performs neither write nor login.
8. A conflicting global URL still fails closed.
9. Post-login unknown health still returns
   `CONNECTOR_HEALTH_UNAVAILABLE`.
10. OAuth URLs and credentials are not persisted anywhere in governance-owned
    state.

The complete shell suite and release gate must pass.

## Out of scope

- Installing MCP separately in every application repository.
- Scanning all repositories on the workstation.
- Editing Cursor's undocumented database or IDE settings.
- Changing GitHub Team role resolution from #29.
- Relaxing connector health or capability gates.
- Publishing `v1.0.4` before #29 and #30 are merged and the final release gate
  passes.
