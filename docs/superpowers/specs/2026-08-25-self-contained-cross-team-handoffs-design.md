# Self-Contained Cross-Team Handoffs Design

## Problem

Commit `559fdc6739222ba74aa16c1f221b55dff55e962f` restores trusted Codex
Jira and Confluence capability detection, but the Confluence target gate is
still allow-by-default. A cross-team handoff can therefore pass when its parent
is the Backend space homepage, its body points at a private provider repository,
and its public API or WebSocket contract is incomplete. Incident page
`85360641` demonstrates the gap.

Prompt guidance already asks agents to use a Folder, but the runtime does not
enforce that guidance or inspect the body for Codex and Claude. Cursor checks
only legacy Jira/GitHub/Canonical markers. This permits a false
`READY_FOR_FE` state even though the recipient cannot implement from the page.

## Goals

- Make cross-team Confluence handoffs self-contained and usable without either
  team knowing the opposite GitHub repository.
- Require an exact reviewed `ACTIVE` capability Folder before a handoff write.
- Validate the actual proposed page body before create or update.
- Keep `DRAFT` useful without allowing it to claim recipient readiness.
- Require full validation and readback before reporting `READY_FOR_FE`.
- Apply equivalent validation through Codex, Claude, and Cursor paths.
- Preserve existing routing, role, OAuth, connector, assignment, and exact-ID
  stop conditions.

## Non-goals

- Changing an application API or WebSocket contract.
- Granting cross-team GitHub access or discovering an opposite-team repository.
- Automatically creating or activating a Confluence Folder.
- Automatically modifying incident page `85360641`.
- Building a webhook, daemon, renderer, general Markdown parser, or schema
  registry service.

## Chosen Approach

Add an explicit `confluence-handoff-write` operation beside ordinary
`confluence-write`. The new operation receives the actual proposed Markdown
body with `--handoff-body-file PATH` and validates it before connector
inspection. This avoids tightening unrelated Confluence writes and avoids a
sidecar JSON manifest that could disagree with the page sent to Atlassian.

The body begins with a small machine-readable header and then uses required
Markdown sections. The header supplies exact routing and state facts; the
sections carry the complete human-readable contract. The validator checks
structure, non-empty content, forbidden repository references, impact-specific
contract sections, and placeholders. It does not attempt to prove the business
correctness of a documented payload.

## Command Contract

The pre-write command is:

```text
beroka-governance preflight REPO \
  --client codex|claude|cursor \
  --operation confluence-handoff-write \
  --non-interactive \
  --confluence-action create|update \
  --target-content-id new|CONTENT_ID \
  --expected-parent-id ACTIVE_FOLDER_ID \
  --handoff-body-file PATH
```

`move` remains an ordinary target operation and cannot publish readiness.
`confluence-handoff-write` rejects a missing, symlinked, non-regular, empty, or
unsafe body file before probing a connector.

The post-write command is the existing `confluence-handoff-verify`, extended
with:

```text
--handoff-body-file PATH
--readback-parent-id ID
--readback-space-key KEY
--readback-title TITLE
--readback-version POSITIVE_INTEGER
--readback-owner-account-id ACCOUNT_ID
```

Verification requires a numeric target content ID and exact readback evidence.
It repeats body and Folder validation, checks the routed space and expected
parent, and requires non-empty title and owner plus a positive page version.
Only this successful verification authorizes an agent to report
`READY_FOR_FE`; a pre-write PASS alone never does.

## Body Contract

Every handoff body starts with exactly one header:

```text
Handoff schema: 1
Handoff state: DRAFT | READY_FOR_FE
Provider Jira: BB-42
Consumer Jira: BF-69
Confluence content ID: new | 85360641
Confluence page version: pending | positive integer
Owner account ID: Atlassian account ID
Effective date: YYYY-MM-DD
Supersedes: N/A | numeric content ID and version
Superseded by: N/A | numeric content ID and version
API impact: affected | none
WebSocket impact: affected | none
Missing sections: comma-separated names | None
```

Provider and consumer keys must be opposite `BB`/`BF` projects and each must
occur exactly once in the header. Cross-team content may contain Jira keys,
Atlassian Jira URLs, Confluence content IDs, and Atlassian Confluence URLs. It
rejects GitHub URLs, Git remotes, repository/branch/commit instructions, and
the legacy `Canonical:` repository marker. Team-local Jira records may retain
their own repository linkage, but a body passed as cross-team handoff content
may not.

These top-level sections define a complete handoff. `READY_FOR_FE` requires
all of them with non-placeholder content; `DRAFT` may omit only sections named
explicitly by `Missing sections`:

- `Purpose and delivered behavior`
- `Affected user flows, assumptions, and non-goals`
- `Authentication and authorization`
- `Public data types and compatibility`
- `State and delivery semantics`
- `Errors and edge cases`
- `Frontend implementation guidance`
- `Sanitized examples and validation evidence`
- `Known limitations and unverified items`
- `FE acknowledgment`

`API impact: affected` additionally requires:

- `Affected API inventory`
- `API operation: <METHOD> <PUBLIC_PATH>` for every affected operation
- within each operation: permissions, headers, path parameters, query
  parameters, request payload, success status and payload, stable public errors,
  pagination, idempotency, retry, cache, timestamp semantics, and sanitized
  request/response examples
- `Unaffected API inventory`

`API impact: none` requires `API impact rationale` and an explicit statement
that no public API operation changes.

`WebSocket impact: affected` additionally requires:

- `Affected WebSocket inventory`
- public connection URL and authentication
- subscribe and unsubscribe requests
- event envelope and affected message payloads
- ordering, deduplication, replay/resume, reconnect, heartbeat, timeout,
  backpressure, error events, close codes, and sanitized message examples
- `Unaffected WebSocket inventory`

`WebSocket impact: none` requires `WebSocket impact rationale` and an explicit
statement that no public WebSocket contract changes.

The validator rejects empty sections and common unresolved placeholders such
as `TBD`, `TODO`, `<placeholder>`, or `fill later`. It rejects reusable secrets
and explicitly named internal topics, topology, adapters, providers, or raw
upstream payloads when they appear as publication claims. This is a structural
and leakage gate, not a substitute for human contract review.

## State Rules

`DRAFT`:

- requires an exact `ACTIVE` Folder;
- must use `Confluence content ID: new` and `page version: pending` for create;
- may omit incomplete contract sections;
- must list every omitted section in `Missing sections`;
- cannot contain `READY_FOR_FE` outside the state value list or claim recipient
  readiness.

`READY_FOR_FE`:

- requires `Missing sections: None`;
- requires every common and impact-specific section;
- is update-only and requires a numeric content ID plus positive page version;
- requires a pre-write PASS, successful Atlassian write, and a subsequent
  `confluence-handoff-verify` PASS before readiness is reported.

## Parent Folder Enforcement

For `confluence-handoff-write`, the expected parent must match exactly one row
for the routed repository in
`runtime/integrations/beroka-be-fe.confluence-targets` with:

- record type `folder`;
- state `ACTIVE`;
- the exact numeric content ID;
- parent equal to the catalog Confluence root;
- matching scope/domain/transport when those optional target fields are
  supplied.

The catalog root itself, a page, `LEGACY`, `PLANNED`, `DRIFTED`,
`UNACTIVATED`, untracked, unrelated, duplicated, or ambiguous targets return
`FOLDER_CREATION_REQUIRED` before connector inspection. The remediation names
the requested scope/domain/transport when known and asks for a user-created or
user-confirmed exact Folder ID. The agent never creates or activates a Folder
silently.

Ordinary `confluence-write` retains its current allow-by-default behavior so
this issue does not change unrelated documentation writes.

## Client Enforcement

- Codex and Claude instructions require the explicit handoff operation with a
  temporary file containing the exact body passed to Atlassian.
- Cursor classifies a Confluence create/update as cross-team when the exact
  body contains the handoff schema and opposite BB/BF Jira header. It validates
  that body in-process and invokes the same operation before allowing the MCP
  call.
- Cursor rejects a cross-team-shaped body that is partial or malformed rather
  than falling back to ordinary `confluence-write`.
- Cross-team Jira intake and acknowledgment text rejects GitHub URLs. Cursor
  checks the actual Jira description/comment body; Codex and Claude use the
  same body validator before `jira-intake-write` or a cross-team acknowledgment
  update. Team-local Jira fields outside the handoff flow remain unchanged.

The three clients must produce the same stable result class for the same body
and target fixture.

## Failure Results

- `FOLDER_CREATION_REQUIRED`: parent is absent, root, non-`ACTIVE`, untracked,
  unrelated, duplicated, or ambiguous.
- `HANDOFF_BODY_REQUIRED`: the actual body cannot be read safely.
- `HANDOFF_BODY_INVALID`: required header or structural content is missing,
  malformed, contradictory, or contains placeholders.
- `CROSS_TEAM_LINK_SCOPE_DENIED`: cross-team content contains a GitHub or
  repository-dependent reference.
- `HANDOFF_READBACK_REQUIRED`: post-write identity, parent, space, title,
  version, owner, or exact body evidence is incomplete or mismatched.

All failures occur before the dependent connector/write action and use
privacy-safe diagnostics without echoing body content, repository identities,
credentials, or raw payloads.

## Tests

Focused shell fixtures cover:

- incident page `85360641` as a root-parent, GitHub-linked, summary-only false
  readiness negative case;
- homepage, page, legacy, untracked, ambiguous, and wrong-domain parents;
- DRAFT with declared omissions and DRAFT false-readiness attempts;
- READY API-only, WebSocket-only, combined, and explicit-no-impact positives;
- every required API and WebSocket subsection as a one-at-a-time negative;
- GitHub URL and repository-dependent instruction rejection in Confluence and
  cross-team Jira bodies;
- secret/internal-detail leakage patterns;
- exact readback identity, parent, space, version, title, owner, and body;
- equivalent Codex, Claude, and Cursor outcomes;
- preservation of ordinary allow-by-default Confluence writes and all existing
  capability, OAuth, role, routing, and inventory failures.

The full shell suite, syntax checks, documentation architecture checks, and
`git diff --check` must pass. Live Jira/Confluence mutation and incident-page
remediation remain outside implementation validation.

## Rollout

This change must ship with the inventory fix in a reviewed governance release.
Before release, qualify a source-pinned runtime against the incident proposal
and confirm it fails before any Atlassian write. Then test one complete handoff
under an exact reviewed `ACTIVE` Folder, read it back, and confirm the page is
self-contained and contains no GitHub URL. Publishing the release and changing
live Jira/Confluence still require separate authorization.
