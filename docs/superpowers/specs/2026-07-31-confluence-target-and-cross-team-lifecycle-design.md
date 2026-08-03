# Confluence Target and Cross-Team Lifecycle Design

Status: Proposed for issue #44 — approved direction, written-spec review pending

## Incident and evidence

[Governance issue #44](https://github.com/beroka-vn/beroka-ai-governance/issues/44)
reports that a broad `confluence-write` preflight passed before REST Market API
content was written into a WebSocket contract.

Read-only validation on 2026-07-31 confirmed:

- Confluence content ID `70713366` is titled
  `BB-11 — Market Data — Derivative Quote Stream Contract` and has parent
  folder `71303169`, `Market — WS`.
- Version 5 of that page contains
  `GET /v1/companies/symbols?group_code=FU_INDEX` and describes it as a Market
  API endpoint.
- Jira `BF-21` treats page `70713366` as a canonical reference and includes
  private Backend GitHub links in its description.
- The Backend Confluence space contains legacy generic folders
  `Market — API` (`71237633`) and `Market — WS` (`71303169`).
- No Backend Capability Registry, canonical FU_INDEX API page, or canonical
  globally unique API folder is currently discoverable.
- Jira `BB-27` is assigned to the Backend owner and is `In Review`; Jira
  `BF-21` is assigned to the Frontend owner and is `To Do`. Both projects expose
  `To Do`, `In Progress`, `In Review`, and `Done`.

The current CLI explains the incident. `confluence-write` validates only the
routed space/root and connector capability. It accepts no content ID,
Capability ID, scope, domain, transport, expected parent, or Registry row.
The stronger documentation rules therefore are not executable preflight
inputs. Cursor also classifies Atlassian tools as Jira or unknown rather than
having a separate Confluence write boundary.

## Decisions

1. Central governance owns a reviewed, machine-readable Confluence target
   inventory. Repository-local metadata and title similarity cannot override
   it.
2. Every Confluence create, update, move, and handoff validation is bound to an
   exact target and transport before connector execution.
3. Known drift is represented explicitly and always fails closed.
4. Supported Codex CLI, Claude Code, and Cursor agents consume one
   provider-neutral rule contract. Future client adapters must install and
   verify the same contract before being declared supported.
5. Cross-team Jira intake remains symmetric, but each team owns and updates its
   own Jira work item. Confluence is the cross-team documentation and handoff
   surface.
6. Cross-team `Task`, `Bug`, and `Feature` creation is allowed through the
   reviewed intake boundary. Creating an Epic in the other team's project
   requires explicit receiving-team confirmation because that team owns its
   planning hierarchy.
7. An agent updates a Jira item only after comparing the authenticated
   Atlassian account ID with the item's current assignee account ID. A mismatch
   or unassigned item returns `ASSIGNEE_CONFIRMATION_REQUIRED` and waits for an
   exact user decision.
8. Opposite-team private GitHub links, branches, commits, Issues, PRs, and
   repository paths are not copied into cross-team Jira descriptions or
   handoff updates. Canonical shared documentation links point to Confluence.
9. Status maintenance is mandatory while an agent is actively executing the
   work, but remains agent-driven. This release adds no daemon, webhook, or
   background event listener.
10. This issue does not perform live Jira or Confluence remediation, change a
    release version, merge a PR, tag, or publish a release.

## Confluence target inventory

Add one tab-separated inventory under `runtime/integrations/` with one reviewed
row per Confluence page or folder relevant to governed cross-team work. Each
row stores:

```text
repository  record-type  state  content-id  title  scope  domain  transport  parent-id  capability-id  registry-content-id
```

Allowed record types are `page` and `folder`. Allowed states are:

- `ACTIVE`: every required field is exact and the target may be considered by
  preflight;
- `PLANNED`: the canonical parent and Registry row are reviewed, but the page
  does not exist yet;
- `DRIFTED`: a known page has conflicting metadata, hierarchy, or content and
  no write may pass;
- `LEGACY`: a generic folder is known but cannot be selected as a canonical
  parent.

`ACTIVE` page rows require an uppercase-kebab-case Capability ID, exact scope,
domain, `API` or `WebSocket` transport, numeric content/parent/Registry IDs,
and an `ACTIVE` canonical parent folder. `PLANNED` rows require the same
mapping except that page content ID is `-`. `DRIFTED` and `LEGACY` rows may use
`-` only for metadata that is demonstrably absent; they remain deny-only.

The first inventory records the observed deny-only state:

- folder `71237633`, `Market — API`, as `LEGACY`;
- folder `71303169`, `Market — WS`, as `LEGACY`;
- page `70713366` as `DRIFTED`, known target transport `WebSocket`, and parent
  `71303169`.

It does not invent a Capability ID, Registry row, canonical parent, or API page.
Those targets remain unavailable until a separately approved live remediation
returns exact IDs and a reviewed governance catalog change publishes them.

Release validation rejects malformed, duplicate, cross-repository, conflicting,
symlinked, or incomplete active inventory rows.

## Target-bound preflight

`confluence-write` requires these additional arguments:

```text
--confluence-action create|update|move
--target-content-id <numeric ID|new>
--capability-id <UPPERCASE-KEBAB-ID>
--scope Shared|Derivatives|Underlying
--domain Market|User
--transport API|WebSocket
--expected-parent-id <numeric ID>
--registry-content-id <numeric ID>
```

Add `confluence-handoff-verify` with the same target arguments. It validates a
canonical document before Jira or an opposite-team capability index may link
it. The write operation continues to require provider create/read capability;
the handoff operation requires provider read capability only.

Target resolution happens after exact repository routing but before connector
inspection:

1. Reject missing or malformed arguments with `ROUTING_REQUIRED`.
2. Resolve exactly one inventory row by repository and target identity.
3. If the row is `DRIFTED` and intended transport differs from its known
   transport, return `MAPPING_CONFLICT` and print both transports.
4. If the row is `DRIFTED` without a transport mismatch, return
   `ROUTING_REQUIRED` with its missing canonical metadata.
5. If the requested parent is `LEGACY`, or no reviewed canonical parent exists,
   return `FOLDER_CREATION_REQUIRED`.
6. If an `ACTIVE` row conflicts on Capability ID, scope, domain, transport,
   parent, Registry row, or content ID, return `MAPPING_CONFLICT`.
7. Continue to connector capability/authentication only after every target
   field matches.

For the reported reproduction, an API update to content `70713366` returns:

```text
Target content ID: 70713366
Intended transport: API
Target transport: WebSocket
Result: MAPPING_CONFLICT
```

No Atlassian connector command may execute on that failure path.

## Pre-write and post-write readback

For update and move operations, the agent first reads the exact content ID and
compares live space, title, parent ID/type, metadata, and transport with the
reviewed inventory. It never resolves a target by similar title. For create,
the agent requires a `PLANNED` row and active canonical parent before creation.

After a successful write, the agent reads back the returned content ID and
verifies:

- space and content ID;
- parent ID and `parentType = folder`;
- Capability ID, scope, domain, transport, and Registry reference;
- document revision and intended changed sections.

Unknown target metadata returns `ROUTING_REQUIRED`. A missing folder returns
`FOLDER_CREATION_REQUIRED`. A post-write hierarchy mismatch returns
`DOC_HIERARCHY_FAILED`. A consumer that cannot open the canonical Confluence
page returns `CROSS_SPACE_ACCESS_REQUIRED`. The agent asks the user and waits
whenever no exact target exists or more than one interpretation remains.

## Supported-client contract

The provider-neutral rules live once in the runtime rule pack and are included
by every supported client adapter:

- Codex: managed `AGENTS.md` block;
- Claude Code: managed `CLAUDE.md` block;
- Cursor: managed User Rule plus local security hook;
- future clients: adapter installation, Doctor verification, and conformance
  tests are required before support is advertised.

Codex and Claude must run target-bound preflight and exact MCP readback because
their supported producer surfaces do not expose a governance hook around every
MCP call. Cursor additionally hard-blocks Confluence write payloads that lack
the required target contract or conflict with the inventory. Governance does
not claim enforcement for an unknown or unenrolled agent.

## Cross-team Jira ownership

### Creation

The requesting team may create a `Task`, `Bug`, or `Feature` through
`jira-intake-write` in the receiving project after duplicate search and create
metadata validation. Reporter/requester remains the requesting identity.
Assignee may be set only when the user or receiving team confirms the exact
receiving-team account ID; otherwise it remains unassigned for triage. Sprint
and receiving-team parent remain unset.

An Epic in the opposite project is not ordinary intake. It requires an exact
receiving-team confirmation of project, Epic objective, owner, and initial
child before creation.

### Update authority

Before any Jira description, field, comment, or status update, the agent reads:

- the authenticated Atlassian account ID;
- issue project/key, reporter, assignee, status, and parent;
- the current receiving repository and ownership boundary.

The authenticated account must equal the current assignee. Otherwise the agent
returns `ASSIGNEE_CONFIRMATION_REQUIRED`, shows both account IDs, and waits for
the user to authorize reassignment or the specific update. Cross-team intake
creation does not grant later update authority. FE updates BF items; BE updates
BB items.

### Link boundary

A team-owned Jira item may retain links to its own repository. A cross-team
Jira description or handoff update must not copy links or paths from the
opposite team's private GitHub repository. It contains the outcome, acceptance
criteria, ownership, and accessible Confluence references. Cross-team durable
API, WebSocket, behavior, examples, and handoff state live in exact Confluence
pages.

A conflicting opposite-team private link returns
`CROSS_TEAM_LINK_SCOPE_DENIED`. Missing accessible Confluence documentation
returns `ROUTING_REQUIRED` or `CROSS_SPACE_ACCESS_REQUIRED`; it is not replaced
with a private repository link.

## Jira and GitHub lifecycle

The symmetric provider/consumer lifecycle is:

1. Requesting team creates or links its consumer item and creates intake in the
   provider project.
2. Provider triages, confirms the assignee, and accepts/rejects the intake.
3. Provider assignee starts work and moves the provider item to `In Progress`.
4. Provider agent creates exactly one Issue in the provider repository after
   readiness and duplicate checks.
5. A provider human marks the PR ready for review. The agent moves the provider
   Jira item to `In Review` at that time.
6. A provider human merges the reviewed PR. `Closes #...` normally closes the
   Issue; the agent closes it manually only after exact merge/link readback
   proves it remains open and the operation is authorized.
7. The provider agent updates the exact Confluence target, reads it back, and
   publishes the handoff state such as `READY_FOR_FE`.
8. The provider assignee completes the provider Jira item when its delivery and
   documentation are complete. The consumer team reviews through Confluence
   and updates only its own consumer Jira item through `In Progress`,
   `In Review`, and `Done`.

`In Review` therefore begins before merge and may remain while provider review
or required consumer acknowledgment is pending. It is not first applied after
merge. Each transition reads available Jira transitions first and reads back
the new status; a missing transition fails closed.

## Cursor enforcement

Cursor tool classification gains an explicit Confluence provider branch.
Before Confluence create/update/move it extracts the content ID, body metadata,
parent, and action, then invokes target-bound preflight. Missing structured
metadata, legacy parent, drift, or transport mismatch denies the MCP execution.

For Jira, Cursor continues to allow cross-team create only through exact intake
routing. Cross-project update remains denied. Same-project update payloads must
carry the work-item language marker and are governed by the assignee/readback
rule. Payloads that copy the opposite repository's private links are denied.

## Remediation for the reported records

This repository change documents but does not execute live remediation:

1. Keep content `70713366` blocked as `DRIFTED`.
2. A Backend documentation owner creates or confirms the exact globally unique
   API and WebSocket folders, Backend Capability Registry, Registry rows,
   Capability IDs, and canonical page IDs.
3. The owner returns those exact IDs for a reviewed governance inventory update.
4. With separate live-write approval, restore page `70713366` to WebSocket-only
   content and publish the FU_INDEX REST contract on the canonical API page.
5. With separate Jira-write approval, replace opposite-team private GitHub
   links in `BF-21` with accessible Confluence references while preserving its
   Frontend-owned status and assignee.

Until steps 2–3 complete, the canonical API positive path is intentionally
`FOLDER_CREATION_REQUIRED`/`ROUTING_REQUIRED`; governance must not guess it.

## Tests

Regression tests exercise behavior, not only source text:

- `v1.0.5` reproduction: intended API plus target `70713366`/WebSocket fails
  before connector inspection and prints both transports;
- known WebSocket target plus WebSocket intent still fails while the row is
  drifted;
- missing canonical API folder/Registry/page fails closed;
- fixture `ACTIVE` API→API and WebSocket→WebSocket updates pass;
- update cannot omit content ID or reuse broad root-only preflight;
- handoff validation rejects a conflicting transport/Capability ID;
- legacy generic folders cannot become a parent;
- malformed or duplicate target inventory fails release validation;
- Cursor denies ambiguous Confluence writes and opposite-team private links;
- Codex, Claude, and Cursor installed instructions expose the same mandatory
  target, assignee, link, and status contract;
- cross-team create is allowed only through intake, cross-project update is
  denied, and assignee mismatch requires confirmation;
- existing bootstrap, connector, routing, Cursor-hook, documentation, release,
  launcher, and smoke tests remain green.

## Operational limitations

The CLI validates reviewed routing and producer capabilities; it does not store
Atlassian credentials or proxy all MCP traffic. Cursor provides an additional
local hook enforcement surface. Codex and Claude compliance depends on their
managed instructions plus mandatory preflight/readback. A future producer with
no instruction or hook integration is unsupported rather than silently treated
as governed.
