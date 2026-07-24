# Confluence Information Architecture Design

## Goal

Make Backend contracts easy for Frontend developers to discover without
organizing canonical documentation around changeable UI pages. Governance must
prevent agents from creating duplicate contracts or placing pages outside the
reviewed hierarchy.

This design applies to Beroka Backend and Frontend profiles. It changes central
governance rules and templates only; it does not move live Confluence content.

## Selected Model

Use three complementary views:

1. Backend owns canonical capability documentation by product scope, domain,
   and transport.
2. Frontend owns module indexes such as HomePage, Portfolio, and Quote, which
   link to Backend capabilities without copying contracts.
3. Integration Hubs keep current Jira, contract-version, handoff, and ownership
   mappings.

The alternatives were rejected:

- Product-only trees duplicate shared contracts between Derivatives and
  Underlying.
- Frontend-screen trees couple Backend ownership to UI layout and duplicate
  contracts when several screens consume the same capability.
- One large page per Market/User transport becomes difficult to own, review,
  version, and trace.

## Backend Hierarchy

The configured Backend Confluence root contains:

```text
Backend Contracts
├── Backend Capability Registry
├── Shared — Conventions
│   ├── Shared — Conventions — Authentication
│   ├── Shared — Conventions — Error Model
│   ├── Shared — Conventions — Versioning
│   └── Shared — Conventions — WebSocket Protocol & Lifecycle
├── Shared — Market — API
│   ├── Shared — Market — Market Overview — API
│   ├── Shared — Market — Heatmap — API
│   ├── Shared — Market — Money Flow — API
│   ├── Shared — Market — News — API
│   ├── Shared — Market — Events — API
│   └── Shared — Market — Market Indices — API
│       ├── Shared — Market — Index Overview — API
│       ├── Shared — Market — Index Snapshot — API
│       ├── Shared — Market — Index Constituents — API
│       └── Shared — Market — Index History — API
├── Shared — Market — WebSocket
│   ├── Shared — Market — Quote Stream — WebSocket
│   ├── Shared — Market — Market Events — WebSocket
│   ├── Shared — Market — Commands — WebSocket
│   └── Shared — Market — Market Indices — WebSocket
│       ├── Shared — Market — Index Commands — WebSocket
│       └── Shared — Market — Index Stream — WebSocket
├── Shared — User — API
│   ├── Shared — User — Profile — API
│   ├── Shared — User — Portfolio — API
│   └── Shared — User — Orders — API
├── Shared — User — WebSocket
│   ├── Shared — User — Order Sync — WebSocket
│   ├── Shared — User — Portfolio Sync — WebSocket
│   └── Shared — User — Commands — WebSocket
├── Derivatives — Market — API
├── Derivatives — Market — WebSocket
├── Derivatives — User — API
├── Derivatives — User — WebSocket
├── Underlying — Market — API
├── Underlying — Market — WebSocket
├── Underlying — User — API
└── Underlying — User — WebSocket
```

Folders in the `Shared` scope contain behavior genuinely reused by Derivatives
and Underlying. Product-scoped Folders contain only product-specific
capabilities or explicit overlays. An overlay links its base Shared capability
and documents only the delta; it must not copy the base payload.

Canonical capability pages are durable service documentation under `Backend
Contracts`; they are not Epic-owned pages. Epic-specific planning, completion,
and decision pages remain in the reviewed Epic Folder and link to canonical
capabilities. This replaces the ambiguous interpretation that every page
mentioned by an Epic must be moved into that Epic's Folder.

Every native Folder title is globally unique within the tenant. Folder names
encode scope, domain, optional capability group, and transport; agents must not
create generic repeated Folder names such as `Market`, `User`, `API`, or
`WebSocket`.

`Market Indices` is a Market capability group, not a top-level domain and not a
Frontend navigation index. Its API and WebSocket Folders use distinct full
names. It becomes a top-level domain only if it later has an independent
service, owner, release lifecycle, and contract.

## Page Granularity

The normal unit is exactly one page and one immutable Capability ID per
capability, not one page per endpoint and not one page for an entire domain.
A navigation Folder such as Market Indices groups related capabilities but has
no Capability ID.

Adding an endpoint or message to an existing capability updates its canonical
page. It does not create a sibling page solely because a new Jira item or pull
request exists. A new page and Capability ID are required only for a distinct
contract capability with its own purpose and lifecycle.

Every WebSocket capability page has these sections:

```text
Connection and authorization
Client → Server Commands
Server → Client Events
Payload references, sanitized examples, and documented delta
Ordering, replay, and idempotency
Error and reconnect behavior
Contract version and changelog
```

The shared WebSocket Protocol & Lifecycle page defines connection-wide
behavior. Capability pages link it and document only capability-specific
behavior. Confluence never copies an authoritative OpenAPI, JSON Schema, or
event schema; it links the exact repository artifact/version/commit.

## Naming and Stable Identity

Native Folder titles use one of these globally unique forms:

```text
<Scope> — Conventions
<Scope> — <Domain> — <Transport>
<Scope> — <Domain> — <Capability group> — <Transport>
```

Examples include `Shared — Market — API`, `Derivatives — User — WebSocket`,
and `Shared — Market — Market Indices — API`. Generic Folder titles are
invalid even when their parents differ.

Canonical capability page titles use:

```text
<Scope> — <Domain> — <Capability> — <Transport>
```

Shared convention page titles use:

```text
Shared — Conventions — <Topic>
```

Examples:

```text
Shared — Market — Heatmap — API
Shared — Market — Index Snapshot — API
Shared — User — Portfolio Sync — WebSocket
Derivatives — Market — Funding Rate — API
Underlying — Market — Corporate Actions — WebSocket
```

Scope is exactly `Shared`, `Derivatives`, or `Underlying`; domain is exactly
`Market` or `User`; transport is exactly `API` or `WebSocket`.

Title is not identity. Governance resolves existing Confluence content by exact
`contentId`, Backend contract artifacts by repository and path, and mappings by
immutable Capability ID. A rename or move updates the existing content and
must never create a replacement page.

Each canonical page records:

```text
Capability ID:
Base Capability ID: <ID | N/A>
Capability Registry reference:
Scope: Shared | Derivatives | Underlying
Domain: Market | User
Transport: API | WebSocket
Canonical contract: <repository/path, version, commit>
Document revision:
Owner:
Frontend consumers:
Confluence content ID:
```

Capability IDs are uppercase kebab case. Exactly one semantic capability, one
transport, and one canonical Confluence page own each ID. Navigation Folders do
not have IDs. Related API and WebSocket capabilities use distinct IDs, for
example:

```text
MARKET-INDEX-OVERVIEW
MARKET-INDEX-SNAPSHOT
MARKET-INDEX-CONSTITUENTS
MARKET-INDEX-HISTORY
MARKET-INDEX-STREAM
```

Product overlays receive distinct IDs and record their base Capability ID.

## Backend Capability Registry

`Backend Capability Registry` is the canonical cross-Epic index:

| Capability ID | Scope | Domain | Transport | Canonical artifact/version/commit | Confluence content ID | Base Capability ID | Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |

One Registry row maps one Capability ID to one semantic capability and one
canonical page. Contract version belongs to the machine-readable repository
artifact, not to a Confluence hierarchy or Epic. Several capability pages may
therefore reference the same OpenAPI version; a separately published
WebSocket/event artifact may have a different version. Document revision
remains page-specific.

Every Epic Integration Hub references the required Registry rows and owns only
Epic-specific Jira relationships, consumers, handoff states, and
acknowledgements. A capability reused by several Epics keeps one Registry row
and appears as a reference in each Hub.

The exact Registry content ID must be allowlisted by reviewed central
Governance before capability-dependent writes. Until it is configured, return
`ROUTING_REQUIRED`; never discover the Registry by title similarity.

## Frontend Hierarchy

The Frontend Confluence space contains durable module indexes:

```text
Frontend Capability Indexes
├── HomePage — Capability Index
├── Portfolio — Capability Index
└── Quote — Capability Index
```

Each index contains:

| FE feature/use | Capability ID | Product scope | Transport | Canonical content ID | Artifact/version | FE owner |
| --- | --- | --- | --- | --- | --- | --- |

Indexes link exact Backend content IDs and contract versions. They never copy
Backend request, response, command, or event payloads.

Changing a component, route, layout, or FE page title updates the FE index
only. It does not rename, move, or duplicate Backend canonical documentation.
One Backend capability may appear in several FE indexes, and one FE module may
consume several Backend capabilities.

Epic-specific Frontend pages remain under their reviewed Epic Folder. They link
the durable module index and relevant Capability IDs instead of creating a
second contract page.

## Write and Read-back Rules

Before creating or moving a page, the agent must resolve:

1. configured Confluence space and root content;
2. Shared, Derivatives, or Underlying scope;
3. Market or User domain;
4. API or WebSocket transport;
5. exact Capability Registry content ID;
6. existing Capability ID and content ID, or confirmed new capability;
7. exact globally unique parent Folder content ID.

The agent then writes once and reads back the content ID, parent ID, parent
type, title, and Capability ID.

Fail closed using existing results:

- missing or ambiguous scope/domain/transport/target:
  `ROUTING_REQUIRED`;
- required native Folder absent or connector cannot create it:
  `FOLDER_CREATION_REQUIRED`;
- read-back parent differs from the resolved parent:
  `DOC_HIERARCHY_FAILED`;
- one Capability ID assigned to different semantic capabilities, duplicate
  Registry rows, or one capability mapped to conflicting content IDs:
  `MAPPING_CONFLICT`.

Never fall back to a space root, another product tree, a similarly named page,
or a Frontend folder. A local request cannot override this hierarchy; changing
the hierarchy requires a reviewed central Governance change.

## Contract and Documentation Changes

Every relevant GitHub Issue and pull request records:

```text
Canonical document: <content ID/URL or repository/path>
Sections changed:
Change class: docs-only | contract-compatible | contract-breaking
Capability ID:
Contract version: <before → after | N/A>
Document revision: <before → after | N/A for repository files>
Additional related Jira items:
```

Contract behavior remains canonical in the Backend repository. Confluence
explains usage and links the exact artifact/version/commit.

- `docs-only` changes do not bump the contract version.
- version changes follow the canonical artifact's published policy; when it
  uses SemVer, compatible corrections are patch changes, backward-compatible
  additions are minor changes, and incompatible behavior is a major change.

After merge, update the existing page revision, Registry row, referencing
Integration Hub changelogs, and affected FE indexes. A previously acknowledged
contract version becomes `SUPERSEDED`; affected FE owners acknowledge the exact
new version.

## Existing Content and Rollout

This is a prospective canonical standard. It creates no legacy Capability-ID
registry, aliases, or automatic compatibility mapping. Existing live records
remain outside the new standard until a maintainer explicitly corrects them in
a separate reviewed operation.

Governance must not silently alias, rename, delete, or rewrite an old
Capability ID such as `HOME-MARKET-INDEX-CHART`. New work uses only Registry
IDs that satisfy this design. Until the exact new Registry row, page, parent,
and artifact are available, capability-dependent external writes return
`ROUTING_REQUIRED`.

The repository example packet is updated to demonstrate the new standard; this
does not represent or trigger a live Confluence migration.

## Governance Package Changes

Implementation updates:

- `governance.md` and `workflow.md` with the mandatory information
  architecture and write/read-back lifecycle;
- `templates/jira-confluence.md` with hierarchy, metadata, FE Index, and
  documentation-change blocks;
- GitHub Issue and pull-request templates with exact document revision and
  Capability ID traceability;
- Backend, Frontend, and BE–FE runtime profiles so AI sessions load the same
  rules and require the reviewed Registry reference;
- existing package examples so no shipped guidance teaches legacy UI/outcome
  IDs or duplicate Folder names;
- a focused shell test asserting that all runtime and human-facing rule
  surfaces contain the mandatory hierarchy constraints.

No CLI command, routing schema, OAuth behavior, credential handling, release
tag, or live Atlassian content changes in this feature.

## Acceptance Criteria

- Backend canonical documentation follows
  scope → domain → transport → capability.
- Shared contracts are not duplicated in Derivatives or Underlying.
- Market Indices remains under Market with API and WebSocket interfaces.
- WebSocket pages distinguish client commands from server events.
- Each Capability ID maps one semantic capability, one transport, one Registry
  row, and one canonical Confluence page.
- Contract versions follow canonical repository artifacts; document revisions
  remain page-specific.
- FE module indexes link exact Backend capability content and versions without
  copying payloads.
- Capability ID and content ID preserve traceability when titles or FE layouts
  change.
- Agents fail closed rather than create or move content outside the hierarchy.
- New Integration Hubs reference Registry rows rather than owning canonical
  capability definitions.
- No legacy Capability-ID compatibility layer or live migration is created.
