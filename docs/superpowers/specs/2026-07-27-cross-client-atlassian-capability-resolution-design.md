# Cross-client Atlassian capability resolution

## Objective

Allow the same reviewed Atlassian semantic capability to work consistently
through Codex, Claude Code, and Cursor without requiring a new governance
release for every client patch version.

The immediate blocked operation is `jira-issue-write` for the MDL repository.
The same model also covers ordinary Confluence page creation. Administrative
provisioning, Jira board/sprint verification, and Confluence Folder parenting
remain outside this change.

## Root cause

The current production compatibility file contains no evidence rows. When a
client exposes `createJiraIssue` and `getJiraIssue`, the runtime resolver uses
their absence to prove `UNSUPPORTED`, but does not use their presence to prove
the complete semantic operation. It then requires an exact compatibility row
containing client name, exact client version, endpoint, and toolset.

Consequently, a healthy authenticated connector through Codex 0.145.0 resolves
`jira-issue-write` to `UNKNOWN`. A new row and release would be required after
every unrelated client patch upgrade.

This models a provider capability as if it belonged to the AI client. Jira and
Confluence operation semantics are supplied by the Atlassian Rovo MCP endpoint;
Codex, Claude Code, and Cursor are adapters to that provider.

## Evidence sources

Capability resolution uses these independent facts:

1. **Connector health and authentication** prove that the selected client can
   reach the configured endpoint as the current user.
2. **A provider capability record** proves that a reviewed Atlassian endpoint
   contract supports one semantic capability with an exact required toolset.
3. **Authoritative runtime inventory**, when the client supplies it, proves
   whether the current user/session exposes every required tool.

Official provider documentation is sufficient evidence for bounded Jira Issue
and ordinary Confluence Page operations only when the operation also requires
post-write read-back. It is not sufficient for Board, sprint, backlog, or
Folder-parent semantics.

Relevant provider and client contracts:

- Atlassian Rovo MCP supported tools:
  <https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/>
- Cursor Agent CLI `mcp list-tools`:
  <https://docs.cursor.com/en/cli/reference/parameters>
- Claude Code MCP management:
  <https://docs.anthropic.com/en/docs/claude-code/mcp>

Web documentation is never queried dynamically during preflight. Reviewed
evidence is published inside the pinned governance release.

## Compatibility schema

New releases use schema 2 in
`runtime/compatibility/atlassian.tsv`:

```text
# schema=2
# endpoint<TAB>required_tools<TAB>tested_on<TAB>capability<TAB>evidence<TAB>state
```

Allowed values:

- `endpoint`: the exact configured Atlassian MCP URL;
- `required_tools`: a non-empty, sorted, comma-separated allowlisted toolset;
- `tested_on`: an ISO `YYYY-MM-DD` evidence date;
- `capability`: an allowlisted semantic capability;
- `evidence`: `official-contract` or `isolated-pilot`;
- `state`: `SUPPORTED` or `UNSUPPORTED`.

There must be at most one exact row per endpoint and capability. Any malformed
or duplicate record makes the requested capability `UNKNOWN`; it never becomes
`SUPPORTED`.

The initial reviewed schema-2 records are:

```text
https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-issue-write	official-contract	SUPPORTED
https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,getAccessibleAtlassianResources,getConfluencePage	2026-07-27	confluence-page-parent-write	official-contract	SUPPORTED
```

Both records require resource discovery because Atlassian tools consume a
`cloudId`. The Jira record also requires JQL search because the governed create
workflow searches for the intended existing issue before creating once.

`jira-board-verification` and `confluence-folder-parent-write` have no
production record until an isolated live pilot proves their complete
semantics.

Schema 1 remains readable for already-pinned releases. Its existing exact
client/version behavior is unchanged. A user-level CLI update must not make a
repository pinned to `v1.0.1` unreadable.

## Cross-client inventory adapters

Each adapter produces only:

```text
INVENTORY_STATE=COMPLETE|UNAVAILABLE
INVENTORY_TOOLS=<normalized exact names, kept internal>
```

No inventory, schema, credential, OAuth state, or connector response is printed
or persisted.

### Codex

Use the existing app-server `mcpServerStatus/list` response. Only exact
top-level tool keys on the unique Atlassian record are accepted. Similar,
nested, cross-server, duplicated, or malformed keys do not count.

### Cursor

Use `cursor-agent mcp list-tools atlassian`. Parse only exact tool identifiers
from the documented command output. Configuration text, argument descriptions,
similar names, and tools belonging to another server do not count.
A successful command is a `COMPLETE` inventory even when it contains no accepted
declarations; a command failure leaves inventory `UNAVAILABLE`.

### Claude Code

Claude Code does not currently publish a stable non-interactive tool-inventory
command equivalent to Cursor's `mcp list-tools`. Its inventory state is
`UNAVAILABLE`. A healthy authenticated connector may therefore use a reviewed
provider capability record without matching the Claude patch version.

This does not claim that the current Atlassian user has write permission.
Permission is checked by the real operation, whose failure remains fail-closed.

## Resolution algorithm

For one requested semantic capability:

1. Verify repository registration, trusted routing, selected connector, and
   authentication using the existing gates.
2. Load exactly one provider record for the configured endpoint and
   capability.
3. If the provider record is absent, invalid, duplicated, or `UNSUPPORTED`,
   return `UNKNOWN` or `UNSUPPORTED` as applicable.
4. Collect selected-client runtime inventory.
5. If inventory is `COMPLETE` and any provider-required tool is absent, return
   `UNSUPPORTED`.
6. If inventory is `COMPLETE` and every required tool is present, return
   `SUPPORTED`.
7. If inventory is `UNAVAILABLE`, connector health is `PASS`, and the provider
   record is `SUPPORTED`, return `SUPPORTED`.

The client executable version is diagnostic only and is not a capability key.
A future confirmed client regression should be handled by its health adapter or
a narrowly reviewed deny rule; no speculative client-version registry is added
in this change.

User-facing output adds the evidence without exposing the toolset:

```text
Capability: jira-issue-write
Capability state: SUPPORTED
Capability evidence: PROVIDER_CONTRACT
Runtime inventory: COMPLETE|UNAVAILABLE
```

All three clients return the same semantic state for equivalent connector
conditions.

## Write safety

Passing preflight authorizes only the requested operation against trusted
routing. It does not authorize a different Jira project, Confluence root,
cross-repository target, or administrative operation.

Jira Epic/Task creation must:

1. read project issue types and create-field metadata;
2. resolve the exact requested issue type without guessing;
3. search for the intended existing record before creating;
4. create once;
5. read back the returned issue key and validate project, type, summary, and
   required linkage; and
6. never retry creation when the first result is indeterminate.

An indeterminate create returns `CREATION_STATUS_UNKNOWN`. A read-back mismatch
returns the existing applicable validation failure. Neither path creates a
second issue automatically.

Ordinary Confluence Page creation likewise requires exact trusted space/root
routing and read-back of the created content and parent. Folder roots remain
blocked without isolated-pilot evidence.

## Administration boundary

This change does not create Jira Spaces/Projects or Confluence Spaces. The
currently published Rovo MCP tool inventory supports Jira Issue and Confluence
Page operations but does not list those administrative creation operations.
An administrator provisions them once; governance then binds the exact keys and
content IDs through reviewed routing.

The developer is not asked to create Epic/Task/Page records manually after
routing and capability preflight pass.

## Failure behavior

| Condition | Result |
| --- | --- |
| Connector missing | `CONNECTOR_MISSING` |
| Authentication missing or expired | `ATLASSIAN_AUTH_REQUIRED` |
| Provider record absent or invalid | `CONNECTOR_CAPABILITY_REQUIRED`, state `UNKNOWN` |
| Complete inventory lacks a required tool | `CONNECTOR_CAPABILITY_REQUIRED`, state `UNSUPPORTED` |
| Board or Folder capability has no pilot record | `CONNECTOR_CAPABILITY_REQUIRED`, state `UNKNOWN` |
| Write permission denied by Atlassian | Operation failure; no automatic retry |
| Create response indeterminate | `CREATION_STATUS_UNKNOWN`; no automatic retry |

Only the requested connector-dependent operation is blocked. Source work and
current-repository GitHub work remain available.

## Tests

All tests use temporary `HOME`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME` with fake
clients and no real credentials.

Required coverage:

- schema-1 releases retain exact legacy behavior;
- schema-2 Jira and Page provider records validate strictly;
- malformed and duplicate rows resolve `UNKNOWN`;
- Codex complete inventory with all exact tools passes;
- Codex complete inventory missing one required tool is `UNSUPPORTED`;
- Cursor `list-tools` with all exact tools passes;
- Cursor ambiguous, similar, or missing tools does not pass;
- Claude healthy connector with unavailable inventory uses the provider record;
- Codex, Claude, and Cursor patch-version changes do not change capability;
- authentication and connector failures still precede capability resolution;
- Board and Folder operations remain `UNKNOWN`;
- no raw inventory, tool schema, OAuth material, or credentials appear in
  output; and
- no operation retries an indeterminate create.

The full existing bootstrap, connector, routing, launcher, release, smoke, and
documentation suites must remain green.

## Delivery sequence

1. Implement and review this capability change in its own governance PR.
2. Run the complete isolated suite and a fresh-client pilot for all adapters
   available to the maintainer; unavailable clients remain covered by strict
   fakes and manual rollout checks.
3. Do not create a tag or GitHub Release until the maintainer explicitly
   approves the tested candidate.
4. Publish the approved release and update the MDL pin through a reviewed
   repository configuration PR.
5. Start a fresh MDL session, run `jira-write` preflight, and create/read back
   the requested Epic and Task.

Clean-worktree registration and the `.beroka/` repository layout are a separate
design and PR. They do not block this capability fix.
