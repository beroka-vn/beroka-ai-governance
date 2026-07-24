# Repository Routing and Connector Preflight

## Goal

Add reviewed, repository-specific routing to the pinned governance runtime
without allowing a task branch to redirect Jira, Confluence, or cross-repository
writes.

The design supports:

- a safe standalone default for newly registered repositories;
- the existing reviewed Backend–Frontend integration;
- centrally allowlisted profiles and integration mappings;
- explicit client selection for connector-dependent operations; and
- operation-scoped connector capability checks.

Source-only work and Git work in the current repository remain available when
external routing cannot be verified.

## Non-goals

V1 does not:

- provision Jira projects, boards, Confluence spaces, pages, or folders;
- infer dependencies or routing from similar names;
- let repositories define arbitrary rule packs or integration mappings;
- use pending local routing for external writes;
- add a persistent routing cache;
- run connector qualification writes against production content;
- accept, print, log, or store developer API tokens; or
- create, move, delete, overwrite, or push the immutable legacy `v1.0.0`
  sample tag.

## Authority Model

Effective behavior is assembled in this order:

1. mandatory general principles from the pinned governance release;
2. one centrally allowlisted repository profile;
3. zero or one centrally allowlisted integration profile;
4. reviewed repository routing from the trusted default-branch baseline;
5. repository-local rules that may only narrow the effective authority; and
6. task instructions that may only narrow authority unless they provide an
   exact, independently valid authorization.

The runtime loads only the selected profile and integration profile. It does
not load every Backend, Frontend, and standalone rule set for every repository.

`DEPENDENCY_STATE` is derived runtime output. It is never stored in repository
configuration. Selecting an integration profile makes a reviewed mapping
available; it does not prove that a particular task has a dependency. A
dependency becomes active only after its exact mapping is verified.

## Repository Routing File

The repository routing file is `.beroka-governance.conf` at the Git root. It is
a strict allowlisted `KEY=VALUE` file and is never sourced, evaluated, or
executed.

V1 allows:

```text
SCHEMA_VERSION=1
PROFILE=backend
JIRA_PROJECT_KEY=BB
JIRA_BOARD_ID=34
CONFLUENCE_SPACE_KEY=Berokaback
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=beroka-be-fe
CROSS_REPO_POLICY=profile-controlled
```

Allowed values are:

| Key | V1 rule |
| --- | --- |
| `SCHEMA_VERSION` | Required and exactly `1`. |
| `PROFILE` | Required; `standalone`, `backend`, or `frontend`. |
| `JIRA_PROJECT_KEY` | Required before Jira writes. |
| `JIRA_BOARD_ID` | Optional; required only for board, backlog, or sprint verification. |
| `CONFLUENCE_SPACE_KEY` | Required before Confluence writes. |
| `CONFLUENCE_ROOT_CONTENT_ID` | Required before Confluence writes. |
| `CONFLUENCE_ROOT_CONTENT_TYPE` | Required before Confluence writes; `page` or `folder`. |
| `INTEGRATION_PROFILE` | Required; `none` or a profile allowlisted by the pinned release. |
| `CROSS_REPO_POLICY` | Required; `explicit-only` or `profile-controlled`. |

Unknown keys, duplicate keys, malformed lines, unsupported schema versions,
invalid values, symlinks, and inconsistent profile combinations make that file
invalid. An invalid trusted baseline returns `ROUTING_INVALID`. An invalid
local candidate remains `ROUTING_CHANGE_PENDING` and is reported as invalid
without becoming effective. Blank lines are allowed; shell expansion and
executable syntax are not.

V1 validates these combinations:

- every repository using `INTEGRATION_PROFILE=none` uses
  `CROSS_REPO_POLICY=explicit-only`;
- `standalone` always uses `INTEGRATION_PROFILE=none`;
- `backend` and `frontend` may select `beroka-be-fe` only when the pinned
  central profile allows the canonical repository; and
- an integrated repository may narrow `profile-controlled` to
  `explicit-only`, but may not broaden authority beyond its central profile.

Future combinations require a reviewed governance release. A repository cannot
introduce one by naming it locally.

## Profile Behavior

### Standalone

Standalone behavior is:

- `DEPENDENCY_STATE=NO_DEPENDENCY_DECLARED`;
- GitHub Issue, branch, commit, push, and pull request scope is the current
  registered repository;
- Jira scope is the configured project;
- Confluence scope is the configured space and root content;
- no counterpart discovery, Integration Hub link, or cross-repository link is
  inferred; and
- a possible dependency may be reported as a candidate, but any one-off link
  requires an exact target and developer confirmation.

If a long-lived mapping is needed, it is added through a reviewed governance
release and routing pull request rather than an ad hoc local rule.

### Backend and Frontend

`INTEGRATION_PROFILE=beroka-be-fe` enables only the centrally reviewed BE–FE
mapping for allowlisted repositories. Counterpart discovery and handoff
locations come from that mapping, not from name similarity.

Cross-repository linking requires:

- `CROSS_REPO_POLICY=profile-controlled`;
- an exact counterpart allowed by the integration profile; and
- a verified Epic, task, or handoff mapping required by the requested workflow.

Frontend learns the Backend handoff documentation location through this
mapping. It does not search for a likely space, page, Epic, or repository.
The current central inventory contains only a repository/profile allowlist,
not an exact counterpart and workflow mapping. Because the CLI also accepts no
exact cross-repository target, every current `cross-repo-write` fails closed
with `ROUTING_REQUIRED` before inspecting a client.

## Trusted Default-branch Baseline

The trusted baseline is the routing blob fetched from the registered
repository's current remote default branch. The CLI calls it a trusted
default-branch baseline, not a human-reviewed baseline. Human review is
established separately by repository branch protection and review policy.

The canonical remote is the remote identity already validated against
`REPOSITORY` in `.beroka-governance.lock`; its local remote name is not
semantically fixed.

Fresh verification performs:

1. resolve the canonical remote URL without modifying repository configuration;
2. run `git ls-remote --symref` to resolve its current default branch and
   advertised commit;
3. create a temporary bare repository outside the application repository;
4. fetch only the exact default-branch ref with shallow history;
5. require the fetched commit to match the advertised commit;
6. read `.beroka-governance.conf` directly from the fetched commit;
7. compare only that file's presence, mode, and blob content with `HEAD`, the
   index, and the working tree; and
8. delete the temporary bare repository on every exit path.

No fetch, ref, object, checkout, index, config, or worktree change is written
to the application repository. V1 uses a temporary bare repository rather
than a persistent governance cache.

The routing state matrix is:

| Trusted baseline | Local routing | State |
| --- | --- | --- |
| Absent | Absent | `ROUTING_REQUIRED` |
| Absent | Present | `ROUTING_CHANGE_PENDING` |
| Present | Identical in `HEAD`, index, and working tree | `ROUTING_ACTIVE` |
| Present | Different or absent in any local layer | `ROUTING_CHANGE_PENDING` |
| Remote cannot be freshly verified | Any | `ROUTING_VERIFICATION_REQUIRED` |

When routing is active, external operations use only the fetched baseline
content. When routing is pending, local content is displayed only as a pending
candidate and never becomes effective routing.

`ROUTING_CHANGE_PENDING` blocks only Jira, Confluence, and cross-repository
writes whose target depends on routing. It does not block local edits, branch
creation, commits, pushes, GitHub Issues, or pull requests in the current
registered repository.

`ROUTING_VERIFICATION_REQUIRED` has the same scoped effect: it blocks
routing-dependent external writes, not source or current-repository Git work.

## Doctor and Context

Base `doctor REPO` keeps its existing read-only, connector-independent package
checks. It does not contact the application remote for a fresh routing
baseline, inspect OAuth, or fail because the machine is offline.

`doctor REPO --client CLIENT` keeps its existing selected-client dependency,
connector, and authentication health checks. It does not turn optional Folder
or Board capability absence into a global connector failure.

`context REPO` attempts read-only routing resolution so the agent can render
the effective profile and boundaries at session start. If the remote is
offline or unavailable, core governance context remains usable and source-only
work may continue. Output marks:

```text
Routing: ROUTING_VERIFICATION_REQUIRED
External routing-dependent writes: BLOCKED
```

It does not report routing as active from an unverified local or stale remote
copy.

Governance operations that do not require an external connector do not inspect
or trigger OAuth.

## External-write Preflight

External routing-dependent operations use:

```text
beroka-governance preflight REPO \
  --client codex|claude|cursor \
  --operation OPERATION \
  [--non-interactive]
```

`--client` selects exactly one client. `--operation` accepts only operations
defined by the pinned governance release. V1 operation classes are:

| Operation | Required routing | Required capability |
| --- | --- | --- |
| `jira-write` | Jira project | Jira issue write |
| `jira-board-verify` | Jira project and board ID | Board/backlog/sprint verification |
| `confluence-write` with `page` root | Confluence space and root content | Page-parent write and read-back |
| `confluence-write` with `folder` root | Confluence space and root content | Folder-parent page write and read-back |
| `cross-repo-write` | Centrally reviewed exact counterpart and workflow mapping (not currently available) | Not reached while routing is unavailable |

For currently routable operations, preflight:

1. verifies registration and the pinned release;
2. performs fresh trusted-baseline verification;
3. requires `ROUTING_ACTIVE` and validates the baseline schema;
4. selects the central profile and integration profile;
5. checks the fields required by the requested operation;
6. checks the selected client dependency and connector;
7. checks authentication health;
8. resolves the operation-scoped capability; and
9. prints the exact effective target, baseline commit, boundaries, and
   `Result: PASS`.

Routing validation precedes OAuth so invalid routing never causes a browser
prompt.

`cross-repo-write` stops at step 5 with `ROUTING_REQUIRED`; it does not inspect
a connector, print a next-preflight instruction, or report `PASS`.

If authentication is missing, expired, or invalid, interactive preflight
prints `AUTH_REQUIRED`, asks for confirmation, and invokes only the selected
client’s supported OAuth flow. Claude Code prints
`/mcp -> atlassian -> Authenticate` and launches `claude`; Codex and Cursor use
their exact `mcp login atlassian` commands. Non-interactive preflight never
opens a browser; it returns `ATLASSIAN_AUTH_REQUIRED` and prints the same
client-specific remediation without launching the client.

OAuth is interactive only when standard input and output are terminals and
`--non-interactive` is absent. Each external write requires a fresh preflight;
preflight output is not a reusable authorization token.

The selected client and OS keyring continue to own OAuth state and credentials.
No routing or compatibility file contains credential material.

## Connector Capabilities

Capabilities use three states:

```text
SUPPORTED
UNSUPPORTED
UNKNOWN
```

Evidence is evaluated in this order:

1. authoritative runtime capability or complete tool inventory supplied by the
   selected client;
2. a compatibility record from the pinned governance release that identifies
   the client and version, connector endpoint, toolset, semantic capability,
   test date, and explicit supported or unsupported result; and
3. no sufficient evidence, which produces `UNKNOWN`.

Tool presence proves a semantic capability only when its declared input and
output contract covers the complete operation. Tool absence proves
`UNSUPPORTED` only when the inventory is authoritative and complete. Otherwise
it produces `UNKNOWN`.

Web documentation is design and qualification evidence, not a runtime
capability source. Connector qualification that requires writes occurs in an
isolated test tenant and is published in a reviewed compatibility record.

Confluence root schemas allow `page` and `folder`, but `page` is the safe V1
default. Folder-root routing passes only when the connector can validate the
folder, create a page beneath it, and read back the correct `parentId` and
`parentType`. It never falls back to the space root.

Likewise, `JIRA_BOARD_ID` is routing data, not capability evidence. Board,
backlog, or sprint verification passes only when the selected connector proves
the matching operation.

`UNKNOWN` and `UNSUPPORTED` block only the related operation and return:

```text
Operation: <operation>
Capability: <capability>
Capability state: UNKNOWN|UNSUPPORTED
Result: CONNECTOR_CAPABILITY_REQUIRED
```

## Bootstrap Lifecycle

A new repository starts with no trusted routing:

1. register the repository and use central general principles for source-only
   work;
2. add `.beroka-governance.conf` on a branch;
3. validate its syntax locally, while treating it as
   `ROUTING_CHANGE_PENDING`;
4. create commits, push, and open the routing pull request in the current
   repository;
5. merge the reviewed routing file to the remote default branch; and
6. start a new agent session and perform fresh verification before any
   routing-dependent external write.

The pending file cannot route the Jira issue used to approve its own pull
request. The first routing pull request must reference either:

- an exact Jira issue created manually outside the agent's pending routing; or
- an issue in a central governance onboarding project configured independently
  of the repository routing file.

If neither exists, the routing lifecycle state remains the state from the
matrix, onboarding is blocked, and the agent asks the developer to supply one
of these independent issue sources. It does not guess a project or bypass the
workflow.

## Results and Scope

| Result | Meaning and scope |
| --- | --- |
| `ROUTING_REQUIRED` | No trusted routing exists for the requested external operation. |
| `ROUTING_INVALID` | The trusted routing baseline violates the strict schema. |
| `ROUTING_CHANGE_PENDING` | Local routing differs from the trusted baseline; routing-dependent writes are blocked. |
| `ROUTING_VERIFICATION_REQUIRED` | The remote default-branch baseline cannot be freshly established. |
| `DEPENDENCY_MISSING` | The explicitly selected client or required helper is missing. |
| `CONNECTOR_MISSING` | The selected client lacks the configured Atlassian connector. |
| `ATLASSIAN_AUTH_REQUIRED` | Authentication is missing, expired, or invalid. |
| `CONNECTOR_CAPABILITY_REQUIRED` | The requested operation's capability is `UNKNOWN` or `UNSUPPORTED`. |
| `PASS` | Core governance, trusted routing, selected connector, authentication, and requested capability all pass for this preflight. |

A failed check blocks only its dependent scope. No failure may be relabeled as
`PASS`, and no optional connector limitation blocks unrelated source or Git
work.

## Tests

Tests use temporary application repositories, temporary bare remotes, isolated
`HOME`/XDG directories, and fake client executables. They use no real
credentials, keyrings, browsers, Jira projects, or Confluence content.

Coverage includes:

- strict parsing, duplicate and unknown keys, invalid combinations, and
  symlink rejection;
- standalone and allowlisted BE–FE profiles;
- derived dependency state;
- a non-`main` default branch and a canonical remote whose name is not
  `origin`;
- verification that baseline inspection does not change application refs,
  objects, index, worktree, or Git configuration;
- all routing state-matrix rows;
- changes in `HEAD`, index, and working tree independently;
- physical working-tree changes hidden by `skip-worktree` or
  `assume-unchanged`;
- comparison of only `.beroka-governance.conf`;
- offline base Doctor and degraded-but-usable Context;
- fresh online verification before every routing-dependent preflight;
- explicit selection of Codex, Claude Code, and Cursor;
- client-specific OAuth confirmation and non-interactive remediation;
- `SUPPORTED`, `UNSUPPORTED`, and `UNKNOWN`;
- operation-scoped Folder and Board capability failures;
- no fallback from a Folder root to the Confluence space root;
- bootstrap routing without self-authorizing external writes;
- permission for current-repository branch, commit, push, Issue, and pull
  request work while routing is pending; and
- preservation of every existing Git tag, including `v1.0.0`.

## References

- [Confluence Cloud REST v2 Folder API](https://developer.atlassian.com/cloud/confluence/rest/v2/api-group-folder/)
- [Atlassian Rovo MCP supported tools](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/)
