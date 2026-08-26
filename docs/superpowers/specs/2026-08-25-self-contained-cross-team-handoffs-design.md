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
- Apply equivalent fail-closed protection through Codex, Claude, and Cursor
  paths.
- Fail closed when a client cannot expose the actual Confluence write body to
  governance at the tool-call boundary.
- Preserve existing routing, role, OAuth, connector, assignment, and exact-ID
  stop conditions.

## Non-goals

- Changing an application API or WebSocket contract.
- Granting cross-team GitHub access or discovering an opposite-team repository.
- Automatically creating or activating a Confluence Folder.
- Automatically modifying incident page `85360641`.
- Building a webhook, daemon, renderer, general Markdown parser, or schema
  registry service.
- Building an Atlassian MCP proxy for clients without a trusted post-tool
  boundary.

## Chosen Approach

Add an explicit `confluence-handoff-write` operation beside ordinary
`confluence-write`. The new operation receives the actual proposed Markdown
body from a trusted client boundary, stages it as `--handoff-body-file PATH`,
and validates it before connector inspection. This avoids a sidecar JSON
manifest that could disagree with the page sent to Atlassian.

The body begins with a small machine-readable header and then uses required
Markdown sections. The header supplies exact routing and state facts; the
sections carry the complete human-readable contract. The validator checks
structure, non-empty content, forbidden repository references, impact-specific
contract sections, and placeholders. It does not attempt to prove the business
correctness of a documented payload.

Governance may permit a create or update only when it receives the actual body
from the client tool-call boundary. Cursor supplies that body through its hook.
Codex and Claude do not currently expose an equivalent trusted boundary, so
their Confluence create/update operations fail closed instead of trusting a
caller-provided file that could differ from the Atlassian request. Moves remain
target-only operations and do not publish body content.

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

`confluence-handoff-verify` is a read-capability preflight. It receives the
proposed body and exact target/Folder identity:

```text
--handoff-body-file PATH
```

It requires a numeric target content ID, repeats body and Folder validation,
and proves only that the routed read connector is available. Caller-supplied
readback assertions are rejected with `HANDOFF_READBACK_REQUIRED`: a local CLI
argument or result file is not trustworthy evidence that Atlassian returned
that value. This release has no trusted post-tool hook that directly receives
both the write receipt and subsequent read response, so it never emits
`Readback: VERIFIED`. Agents must report the handoff as unverified and must not
report `READY_FOR_FE` until such a trusted runtime path proves exact identity,
parent, space, version, title, owner, and body.

## Body Contract

Every handoff body starts with exactly one header:

```text
Handoff schema: 1
Handoff state: DRAFT | READY_FOR_FE
Provider Jira: BB-42
Consumer Jira: BF-69
Scope: Product
Domain: Broker accounts
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

Provider and consumer keys must be opposite `BB`/`BF` projects, the provider
project must equal the routed team's Jira project, and each key must occur
exactly once in the header. `Scope` and `Domain` are non-placeholder routing
values and must match the selected `ACTIVE` Folder exactly. Cross-team content
may contain Jira keys,
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
- one `WebSocket contract: <PUBLIC_URL>` block for every exact affected
  inventory entry;
- within each contract block: public connection URL and authentication,
  subscribe and unsubscribe requests, event envelope and affected message
  payloads, ordering, deduplication, replay/resume, reconnect, heartbeat,
  timeout, backpressure, error events, close codes, and sanitized message
  examples;
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
- requires a pre-write PASS, successful Atlassian write, and trusted post-tool
  verification of the write receipt plus subsequent read response before
  readiness is reported. The current release has no such verifier, so it must
  report the state as unverified even when the capability-only
  `confluence-handoff-verify` preflight passes.

## Parent Folder Enforcement

For `confluence-handoff-write`, the expected parent must match exactly one row
for the routed repository in
`runtime/integrations/beroka-be-fe.confluence-targets` with:

- record type `folder`;
- state `ACTIVE`;
- the exact numeric content ID;
- parent equal to the catalog Confluence root;
- scope and domain exactly matching the body header;
- transport `API`, `WebSocket`, or `API+WebSocket` matching the body's impact;
- for an update, a tracked target whose recorded parent is this exact Folder.

The catalog root itself, a page, `LEGACY`, `PLANNED`, `DRIFTED`,
`UNACTIVATED`, untracked, unrelated, duplicated, or ambiguous targets return
`FOLDER_CREATION_REQUIRED` before connector inspection. The remediation names
the requested scope/domain/transport when known and asks for a user-created or
user-confirmed exact Folder ID. The agent never creates or activates a Folder
silently.

Cursor retains ordinary allow-by-default `confluence-write` behavior because
its hook sees and classifies the actual create/update body. Codex and Claude
must reject Confluence create/update preflights with
`CLIENT_BODY_GATE_REQUIRED` until a trusted tool-call boundary is installed;
they may still perform target-only moves through the ordinary operation. This
intentional fail-closed restriction prevents either client from selecting an
ordinary operation for cross-team content that governance cannot inspect.

## Client Enforcement

- Codex and Claude reject both ordinary and handoff Confluence create/update
  writes because governance cannot prove that a caller-provided file is the
  actual Atlassian body. Instructions route these writes to Cursor or require a
  future trusted client boundary; they never suggest bypassing the gate.
- Cursor classifies a Confluence create/update as cross-team when any textual
  input contains the new schema, opposite BB/BF Jira evidence, a legacy
  handoff with a private provider GitHub link, or readiness evidence. It
  validates the complete body in-process and invokes the same operation before
  allowing the MCP call.
- Cursor rejects a cross-team-shaped body that is partial or malformed rather
  than falling back to ordinary `confluence-write`.
- Cross-team Jira intake and acknowledgment text rejects GitHub URLs. Cursor
  classifies plain acknowledgments and opposite-project Jira evidence, then
  checks every textual tool-input value, including nested structured fields;
  Codex and Claude use the same body validator before `jira-intake-write` or a
  cross-team acknowledgment update. Intake output exposes only the routed Jira
  project/profile, never the opposite private repository identity. Team-local
  Jira fields outside the handoff flow remain unchanged.

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
- `CLIENT_BODY_GATE_REQUIRED`: the selected client cannot provide the actual
  Confluence create/update body at a trusted tool-call boundary.

All failures occur before the dependent connector/write action and use
privacy-safe diagnostics without echoing body content, repository identities,
credentials, or raw payloads.

## Tests

Focused shell fixtures cover:

- incident page `85360641` as a root-parent, GitHub-linked, summary-only false
  readiness negative case;
- homepage, page, legacy, untracked, ambiguous, and wrong-domain parents;
- exact body scope/domain mismatch against an otherwise valid `ACTIVE` Folder;
- DRAFT with declared omissions and DRAFT false-readiness attempts;
- READY API-only, WebSocket-only, combined, and explicit-no-impact positives;
- every required API and WebSocket subsection as a one-at-a-time negative;
- GitHub URL and repository-dependent instruction rejection in Confluence and
  cross-team Jira bodies;
- secret/internal-detail leakage patterns;
- rejection of caller-supplied readback assertions and capability-only verify
  output that never claims `VERIFIED`;
- Cursor actual-body enforcement plus fail-closed Codex/Claude create/update
  outcomes for both ordinary and handoff operations;
- preservation of Cursor ordinary allow-by-default Confluence writes,
  Codex/Claude target-only moves, and all existing capability, OAuth, role,
  routing, and inventory failures.

The full shell suite, syntax checks, documentation architecture checks, and
`git diff --check` must pass. Live Jira/Confluence mutation and incident-page
remediation remain outside implementation validation.

## Rollout

This change must ship with the inventory fix in a reviewed governance release.
Before release, qualify a source-pinned runtime against the incident proposal
and confirm it fails before any Atlassian write. Then test one complete handoff
under an exact reviewed `ACTIVE` Folder and inspect its actual connector write
receipt plus subsequent read response. Until a trusted post-tool hook binds
those responses, report readback as unverified even when manual inspection
confirms the page is self-contained and contains no GitHub URL. Publishing the
release and changing live Jira/Confluence still require separate authorization.
A later reviewed change may restore Codex/Claude create/update support by
adding a trusted actual-body MCP boundary; caller-provided files alone are not
sufficient.
