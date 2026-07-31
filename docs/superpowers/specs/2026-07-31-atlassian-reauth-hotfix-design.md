# Atlassian Re-authentication Hotfix Design

Status: Approved

Issue: https://github.com/beroka-vn/beroka-ai-governance/issues/36

## Problem

Codex 0.146.0 can report an expired Atlassian refresh token as a timestamped
runtime error while its status response still contains `authStatus: "oAuth"`
and an empty `tools` object:

```text
ERROR codex_rmcp_client::oauth::refresh_transaction: ... server atlassian:
... unauthorized_client: refresh_token is invalid
```

The v1.0.4 classifier recognizes only authentication errors whose trimmed line
starts with `server atlassian:`. It therefore discards the runtime error,
accepts the status response as authenticated, and classifies the empty tool
inventory as `UNSUPPORTED`. Jira preflight then returns
`CONNECTOR_CAPABILITY_REQUIRED` instead of the required
`ATLASSIAN_AUTH_REQUIRED`.

Separately, interactive setup and preflight ask whether to start OAuth. The
approved boundary makes re-authentication mandatory once authentication is
known to be missing, expired, or invalid, and requires the producer-owned flow
to surface its one-time login URL.

## Chosen approach

### Authentication classification

Extend the existing shared Codex authentication classifier with one precise
match for the current Codex refresh transaction:

- the line identifies `codex_rmcp_client::oauth::refresh_transaction`;
- the error identifies `server atlassian`;
- the provider response contains `unauthorized_client`; and
- the response states that the refresh token is invalid.

The existing structured `reauthenticationRequired`, scoped HTTP 401/403, and
healthy status paths remain unchanged. The classifier continues to run before
the status response is reduced to its Atlassian record, so connector health
returns authentication-required before capability inventory is resolved.

An authenticated response with `tools: {}` and no authentication error remains
a complete empty inventory and therefore remains `UNSUPPORTED`.

### Producer-owned login flow

When interactive `setup-connectors`, bootstrap, or preflight classifies
authentication as required, it must immediately call the existing `run_oauth`
path instead of asking the optional `Start OAuth now?` question. Provider
output stays attached to the terminal so the user receives the producer's
one-time URL:

- Codex runs `codex mcp login atlassian`.
- Cursor Agent runs `cursor-agent mcp login atlassian`.
- Claude Code runs `claude mcp login atlassian --no-browser`, which forces the
  producer's URL prompt. Claude Code must support that documented flag; an
  older client returns `DEPENDENCY_MISSING` with `Remediation: claude update`.
  Validate support at this OAuth boundary by requiring `claude mcp login
  --help` to advertise `--no-browser`; do not add a general version parser.

Cursor first-run still requires its existing confirmation before governance
writes a new global MCP configuration. That confirmation protects a separate
configuration-write boundary; after approval, OAuth starts without a second
optional prompt.

After the producer command exits, governance clears its cached probe, checks
connector health again, and proceeds only on verified health. An incomplete or
failed login remains fail-closed.

Non-interactive CLI invocations remain non-interactive: they do not launch a
browser or block an unattended process. They return
`ATLASSIAN_AUTH_REQUIRED` with the exact selected-client remediation, including
the direct Claude command instead of the previous plain `claude` launcher.

### Active agent handoff

The managed Codex, Cursor, and Claude instruction templates must require an
active agent that receives non-interactive `ATLASSIAN_AUTH_REQUIRED` to:

1. stop the dependent external write;
2. invoke the selected producer-owned authentication flow in an interactive
   terminal;
3. stream the producer output so the user can open its one-time URL;
4. never synthesize, parse, persist, or place that URL in an issue, commit, or
   durable log; and
5. rerun a fresh operation-specific preflight after login, continuing only on
   `Result: PASS`.

This agent handoff covers AI-driven preflight while preserving the unattended
contract of `--non-interactive`.

## Producer references

- Cursor Agent documents
  `cursor-agent mcp login <identifier>`:
  https://docs.cursor.com/en/cli/reference/parameters
- Claude Code documents `claude mcp login <name>` from v2.1.186 and
  `--no-browser` URL output from v2.1.191:
  https://code.claude.com/docs/en/mcp
- Codex uses the installed CLI's supported
  `codex mcp login atlassian` command, as confirmed by its local help and the
  approved issue requirement.

No URL is hard-coded because each producer owns OAuth discovery, state, callback
handling, token storage, and URL generation.

## Rejected approaches

- Treating every empty tool inventory as authentication-required would hide a
  genuinely authenticated connector that lacks required tools.
- Broadly matching any `unauthorized_client` log could misclassify another MCP
  server's authentication failure as Atlassian.
- Hard-coding an authorization endpoint would bypass producer discovery and
  cannot safely generate one-time state or callback parameters.
- Starting OAuth inside every non-interactive process would make automation
  hang and violate the explicit non-interactive contract.

## Verification

Add the smallest regression coverage to the existing connector and routing
fixtures:

1. A Codex refresh error followed by `authStatus: "oAuth"` and `tools: {}`
   returns `ATLASSIAN_AUTH_REQUIRED`, not
   `CONNECTOR_CAPABILITY_REQUIRED`.
2. Non-interactive output includes the selected-client remediation and never
   invokes a login command.
3. Interactive Codex setup and preflight invoke
   `codex mcp login atlassian` without the optional OAuth prompt and stream the
   fake producer URL.
4. Existing authenticated empty-inventory coverage remains `UNSUPPORTED`.
5. Codex, Cursor, and Claude managed templates contain the mandatory agent
   handoff.
6. The focused connector/routing tests and complete release suite pass.

## Release scope

Target inclusion in patch release `v1.0.5`. This issue and implementation PR
must not update release metadata. Prepare release-only changes after Issue #35
and Issue #36 are both merged at their exact reviewed commits.

Do not change the Atlassian capability registry, accept developer API tokens,
alter application repositories, merge a PR, create a tag, or publish a release
within this issue.
