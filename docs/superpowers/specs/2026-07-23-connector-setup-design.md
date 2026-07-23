# Client-Selected Atlassian Connector Setup

## Goal

Add explicit, client-specific Atlassian connector setup and health checks for
Codex, Claude Code, and Cursor without making the governance lifecycle depend on
external connectors.

The selected client and its OS keyring continue to own OAuth state and
credentials. The governance CLI never accepts, reads, prints, logs, or stores a
developer API token.

## Scope

The change adds:

- `beroka-governance setup-connectors --client codex|claude|cursor
  [--non-interactive]`;
- interactive client selection when bootstrap invokes `setup-connectors`
  without `--client`;
- client-specific Atlassian connector registration and OAuth commands;
- optional connector health checks through
  `beroka-governance doctor REPO --client codex|claude|cursor`; and
- isolated tests using temporary HOME/XDG directories and fake client
  executables.

The existing `install`, `register`, `update`, `rollback`, `unregister`,
`uninstall`, `context`, `show`, and `doctor REPO` behavior remains
connector-independent.

Bootstrap remains responsible for installing the selected vendor client and
any client-specific helper dependency before invoking `setup-connectors`. This
repository does not add cross-platform installers for Codex, Claude Code, or
Cursor. A missing required executable fails with `DEPENDENCY_MISSING`.

## Client Selection

An explicit `--client` value selects exactly one client. Unsupported values
produce usage and exit status 2. Running setup again with a different explicit
client is supported; no global "selected client" state is stored.

When an interactive bootstrap invokes `setup-connectors` without `--client`,
the CLI checks for `codex`, `claude`, and `cursor-agent` on `PATH`:

- zero detected clients: return `DEPENDENCY_MISSING`;
- one detected client: show the client and ask for confirmation; and
- multiple detected clients: prompt for one client.

Declining the sole detected client, or cancelling the multiple-client prompt,
prints `Result: CANCELLED`, exits successfully, and configures nothing.
Non-interactive invocations must supply `--client`; the CLI never selects a
client from `PATH` in non-interactive mode and never configures every detected
client.

Interactive mode requires readable stdin and a terminal on stdout.
`--non-interactive` always disables prompts and browser-opening authentication,
even when terminals are attached.

## Atlassian Endpoint

All three clients use the current Atlassian OAuth MCP endpoint:

```text
https://mcp.atlassian.com/v1/mcp/authv2
```

The CLI does not offer an API-token configuration path.

## Setup Flow

`setup-connectors` performs these steps for the selected client only:

1. Verify the selected client executable and any required configuration helper.
2. Inspect whether an `atlassian` connector exists with the expected endpoint.
3. If absent, register it using the selected client's supported configuration
   surface without starting OAuth.
4. Probe the selected client's connector health.
5. If healthy, print `Result: PASS`.
6. If authentication is missing, expired, rejected, or requires re-login,
   print `Authentication: AUTH_REQUIRED`.
7. In interactive mode, ask whether to start OAuth. On confirmation, invoke the
   selected client's OAuth command with inherited terminal I/O, then probe
   health again.
8. In non-interactive mode, or when interactive OAuth is declined, do not open a
   browser. Return `ATLASSIAN_AUTH_REQUIRED` and print the exact remediation
   command.

Configuration is idempotent. An existing correct connector is preserved. An
existing `atlassian` connector with a different transport or URL returns
`CONNECTOR_MISSING` with a conflict explanation; setup does not overwrite
unknown user configuration.

## Client-Specific Behavior

| Client | Dependency | Connector registration | Health source | OAuth remediation |
| --- | --- | --- | --- | --- |
| Codex | `codex` with MCP and app-server support | Write `mcp_servers.atlassian` through Codex's config API so registration cannot start OAuth | Codex app-server MCP startup/status result | `codex mcp login atlassian` |
| Claude Code | `claude` with `mcp add`, `list/get`, and `login` support | `claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2` | `claude mcp list/get` connection state | `claude mcp login atlassian` |
| Cursor | `cursor-agent` and `jq` | Atomically merge only `mcpServers.atlassian.url` into global `~/.cursor/mcp.json` | `cursor-agent mcp list` and `list-tools atlassian` | `cursor-agent mcp login atlassian` |

Codex configuration uses its app-server config write surface because the
current `codex mcp add` may immediately begin OAuth discovery and open a browser.
The separate configuration call preserves the required confirmation before
`codex mcp login atlassian`.

Cursor uses a JSON parser because replacing or text-editing an existing
`mcp.json` could destroy unrelated user configuration. The merge is staged in a
temporary file in the same directory and renamed atomically. It writes no
credential fields.

Client status output is captured and normalized; raw status output is not
echoed. The interactive OAuth subprocess owns its terminal output and credential
storage.

## Doctor

`beroka-governance doctor REPO` keeps its current registration and release
checks and does not inspect client dependencies, connector configuration, or
OAuth.

`beroka-governance doctor REPO --client CLIENT` first performs the existing
governance checks, then performs a read-only connector health check for the one
selected client. Doctor never prompts and never invokes an OAuth command.

Connector-aware Doctor distinguishes:

| Result | Meaning |
| --- | --- |
| `DEPENDENCY_MISSING` | The selected client or required client helper is unavailable or lacks the required command surface. |
| `CONNECTOR_MISSING` | The selected client has no compatible `atlassian` connector configuration. |
| `ATLASSIAN_AUTH_REQUIRED` | Authentication is missing, expired, invalid, or requires re-login. |
| `PASS` | Governance validation, dependency checks, connector configuration, and authentication health all pass. |

Other client execution or network failures continue to use
`GOVERNANCE_NOT_READY` with a specific message rather than being mislabeled as
an authentication failure.

When authentication is required, output includes:

```text
Client: <client>
Authentication: AUTH_REQUIRED
Remediation: <client-specific OAuth command>
Result: ATLASSIAN_AUTH_REQUIRED
```

## Connector-Dependent Operations

Only commands that explicitly select a client or otherwise declare connector
use call the connector health check. A later connector-dependent command must
call the same selected-client health function before using Atlassian.

Governance-only operations never check authentication and never trigger OAuth.

## Credential and Output Boundaries

- No CLI option, prompt, config key, or environment-variable contract accepts a
  developer API token.
- The CLI does not enumerate credential files, environment variables, or OS
  keyring entries.
- OAuth commands are delegated to the selected client.
- OAuth credentials and refresh behavior remain owned by the selected
  client/OS keyring.
- Non-interactive mode never invokes a login command or browser flow.
- Health commands have raw stdout and stderr suppressed after classification so
  account details or client internals are not copied into governance output.

## Tests

A focused connector test script creates a temporary root and exports isolated
`HOME`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME`. It places fake `codex`,
`claude`, `cursor-agent`, and `jq` executables first on `PATH`; no real client,
credential store, keyring, connector, or browser is used.

The tests cover:

- explicit selection of each client;
- zero, one, and multiple interactive detections;
- confirmation and selection prompts;
- refusal to auto-select in non-interactive mode;
- `DEPENDENCY_MISSING`, `CONNECTOR_MISSING`,
  `ATLASSIAN_AUTH_REQUIRED`, and `PASS`;
- correct connector registration for each client;
- preservation of unrelated Cursor JSON;
- no login invocation before confirmation;
- exact client-specific login command after confirmation;
- no login invocation in non-interactive mode;
- exact remediation output;
- idempotent repeated setup;
- explicit setup of a second client; and
- governance-only Doctor performing no client command.

The release gate remains:

```bash
sh -n bin/beroka-governance
sh tests/smoke.sh
sh tests/connectors.sh
```

## Release Boundary

No command in this work creates, moves, deletes, or overwrites a Git tag.
Existing `v1.0.0` remains unchanged. Preparing or publishing a later release is
outside this change.

## References

- [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp)
- [Codex app-server](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Cursor Agent CLI parameters](https://docs.cursor.com/en/cli/reference/parameters)
- [Cursor MCP](https://docs.cursor.com/context/model-context-protocol)
- [Atlassian client setup](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/setting-up-clients/)
