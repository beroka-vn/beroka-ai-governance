# Confluence publication through native client hooks

Codex, Claude Code and Cursor use the same Confluence validation and receipt
logic. Bootstrap installs the selected client's hooks; upgrade refreshes hooks
for enrolled clients. To repair an existing installation:

```sh
beroka-governance setup-documentation-hooks --client codex
# Or --client claude / --client cursor
```

Restart with native hooks enabled. Codex uses `$CODEX_HOME/hooks.json` (default
`~/.codex/hooks.json`); Claude uses `~/.claude/settings.json`; Cursor uses
`~/.cursor/hooks.json`. Unrelated settings/hooks are preserved. Never invoke
`confluence-hook` manually as proof that an external operation occurred.

## Publication sequence

1. Run governance context for the exact repository. The authenticated account
   must have the existing repository role and Atlassian write permissions.
2. Call the configured Atlassian `getConfluenceSpaces` tool for the routed space
   key and exact cloud. Its native post-tool event records the returned space ID.
3. Create with `cloudId`, numeric `spaceId`/`parentId`, one `body`, and
   `contentFormat: markdown`. Update requires `cloudId`, `pageId` and `body`;
   `spaceId`/`parentId` are optional. If omitted, first call `getConfluencePage`
   for that page in the same cloud/session so the hook observes its current
   space and parent. These IDs are used only for validation and readback;
   the outbound arguments remain unchanged. The native pre-tool event applies
   the existing role, OAuth, capability, routing and content checks.
4. The post-tool event checks the executed arguments against the pre-tool
   receipt and records the returned ID/version. This is `WRITE_RECORDED`, not
   readback or readiness proof.
5. Call `getConfluencePage` for that ID, same cloud and Markdown format. The read
   must start after the write response. Its post-tool event compares content ID,
   parent, space, version and body. Confluence-added intraword underscore escapes
   are accepted only in a conservative plain-prose subset; code and all other
   bytes remain exact, and ambiguous Markdown stays unverified. The original
   outbound argument/body hashes remain unchanged. Only `READBACK_VERIFIED` proves the
   sequence completed.

Ordinary documentation still needs the existing Jira/GitHub handoff delta
markers. Cross-team DRAFT creation needs the reviewed ACTIVE Folder and schema
body. READY_FOR_FE remains update-only, requires every existing contract section,
and its declared page version must match the actual write/readback version.
Neither ordinary writes nor capability-only preflight can publish readiness.

## Failures and support boundary

Only one write can await verification per client/repository/session. Changed
arguments, unsupported result shapes, failed writes and failed/mismatched reads
never produce completion proof. An indeterminate create must be reconciled by
exact external identity; never automatically create another page. Pending state
is kept under `$XDG_STATE_HOME/beroka-ai-governance/confluence-hooks` (the usual
`~/.local/state` default). Receipts contain identifiers and content hashes, not
bodies or credentials. A Stop hook requests the missing readback; its subsequent
continuation can report the operation as blocked instead of looping forever.
An explicit structured HTTP rejection (400/401/403/404/409/422) releases the
pending slot without success proof. Correct its prerequisite before a new
attempt. Text-only errors and timeouts retain the slot because execution may
have occurred. Failed readback can be retried as a read; never repeat its write.

This adapter supports native MCP hooks with tool-use IDs and structured results.
Codex Apps uses `mcp__codex_apps__atlassian_rovo__*` in native CLI hooks
and `mcp__codex_apps__atlassian_rovo_*` in flattened hosts; direct
Atlassian MCP uses `mcp__atlassian__*`; Cursor generic hooks use `MCP:<tool_name>`.
ADF, preview tools, other connector aliases and hosts that do not deliver native
pre/post events need a reviewed adapter. `CLIENT_BODY_GATE_REQUIRED` describes
the missing configuration/path; it is not an instruction to switch clients.
Standalone body files, environment flags and caller-supplied readback assertions
cannot unlock standalone preflight. Hooks rely on the host's event integrity,
like the existing Cursor boundary; they are not protection against a local user
rewriting governance code, forging hook stdin or disabling hooks.

For another client, add its native event/response adapter and installer to
`src/55-confluence-hooks.sh`, retain the shared validators, and run the same
positive/negative lifecycle cases. Do not add a client-name bypass to preflight.

## Validation evidence

`sh tests/confluence-hooks.sh` exercises the public CLI and each native event
envelope against a pinned fixture release. Connector authentication/inventory
and Atlassian responses are simulated. This is regression evidence, not live
Confluence write evidence or a guarantee that an older client build supports
hooks. No business page is created or modified by the suite.

Local Linux validation on 2026-09-10 passed all ten shell suites: bootstrap,
build, confluence-hooks, connectors, cursor-hooks, documentation-architecture,
launcher, release, routing and smoke (`sh tests/<name>.sh`).
`scripts/build-cli.sh --check` and `git diff --check` also passed.
The native client applications themselves were not launched to perform sandbox
writes; fresh client-session evidence remains a release gate.

Native contracts checked during implementation:
[Codex hooks](https://developers.openai.com/codex/hooks),
[Claude hooks](https://code.claude.com/docs/en/hooks), and
[Cursor hooks](https://cursor.com/docs/hooks).
