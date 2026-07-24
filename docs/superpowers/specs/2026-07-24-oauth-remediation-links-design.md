# OAuth Remediation Links Design

## Goal

When an Atlassian or GitHub operation requires authentication, let the
provider-owned OAuth process show the exact one-time URL to the user without
Beroka Governance reading, storing, or logging OAuth state or credentials.

## Decisions

- Authentication is operation-scoped. Jira and Confluence operations use the
  selected client's Atlassian MCP authentication. `github-write` uses GitHub
  CLI authentication for push and pull-request workflows.
- A healthy authentication check returns `PASS` and never starts OAuth again.
- Interactive auth failures ask for confirmation, then run the provider-owned
  login command directly on the terminal. Its stdout/stderr remains a direct
  pass-through, so the exact OAuth URL or device URL/code is visible without
  Governance capturing it.
- Non-interactive mode never starts OAuth or opens a browser. It fails closed
  and prints the exact command that a user can run interactively. A dynamic
  OAuth URL does not exist until that command starts the provider flow.
- Atlassian failures return `ATLASSIAN_AUTH_REQUIRED`. GitHub failures return
  `GITHUB_AUTH_REQUIRED`.
- Tokens and OAuth state remain owned by Codex, Claude Code, Cursor, GitHub CLI,
  or the OS keyring. Governance never accepts token flags or environment
  values and never calls token-display commands.

## Atlassian Flow

Keep the existing per-client commands:

- Codex: `codex mcp login atlassian`
- Claude Code: launch `claude`, then `/mcp -> atlassian -> Authenticate`
- Cursor: `cursor-agent mcp login atlassian`

Codex connector inspection accepts both the legacy top-level `url` field and
the current `transport.url` field, while still rejecting ambiguity, duplicate
fields, wrong connector names, or unexpected endpoints.

For the Atlassian connector, Codex `authStatus=oAuth` with an empty tool
inventory is authentication-required because a usable authenticated
Atlassian connector always exposes tools. This maps the current Codex
`0.145.0` response to `ATLASSIAN_AUTH_REQUIRED` instead of
`GOVERNANCE_NOT_READY`.

## GitHub Flow

Add `github-write` to preflight. It verifies repository registration but does
not require Jira/Confluence routing, so routing that is absent or pending does
not block branch, push, or pull-request work in the current repository.

GitHub authentication uses:

- Health: `gh auth status --hostname github.com`
- Interactive login: `gh auth login --hostname github.com --web`
- Non-interactive remediation:
  `gh auth login --hostname github.com --web`

The login command runs only after a failed auth check and interactive
confirmation. After the login command returns, Governance checks auth health
again before returning `PASS`.

GitHub CLI is a dependency only for `github-write`; it is not added to
Atlassian-only setup or doctor paths. Unknown GitHub health failures return
`GOVERNANCE_NOT_READY` rather than being mislabeled as OAuth failures.

## Output Contract

Interactive auth-required output identifies the provider and client, asks
whether to start OAuth, and then streams the provider's OAuth output directly.

Non-interactive Atlassian example:

```text
Client: codex
Provider: atlassian
Authentication: AUTH_REQUIRED
Remediation: codex mcp login atlassian
Result: ATLASSIAN_AUTH_REQUIRED
```

Non-interactive GitHub example:

```text
Client: codex
Provider: github
Authentication: AUTH_REQUIRED
Remediation: gh auth login --hostname github.com --web
Result: GITHUB_AUTH_REQUIRED
```

## Tests

Extend isolated shell tests that replace `HOME`, XDG directories, and command
paths with temporary fakes. Tests must prove:

- Codex accepts `transport.url` and reports empty OAuth tools as auth-required.
- Interactive Atlassian OAuth output, including a fake exact URL, passes
  through unchanged and is not written under temporary HOME/XDG directories.
- Healthy GitHub auth does not invoke login.
- Interactive missing GitHub auth invokes login once, passes through a fake
  OAuth URL, rechecks health, and passes.
- Non-interactive missing GitHub auth never invokes login and returns
  `GITHUB_AUTH_REQUIRED` with the exact remediation command.
- `github-write` remains allowed when repository routing is absent or pending.
- Jira/Confluence operations remain unchanged and do not inspect GitHub auth.
