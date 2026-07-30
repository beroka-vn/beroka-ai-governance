# GitHub Team Role Routing Design

Status: Approved

## Problem

The published `v1.0.3` release catalogs
`cuongngo1801-beroka/Beroka_Backend` and
`cuongngo1801-beroka/Beroka_Frontend`. GitHub redirects those transferred
repositories to `beroka-vn`, but governance intentionally matches repository
slugs exactly, so canonical organization clones return `ROUTING_REQUIRED`.

The package also has no verified user role. A Frontend-only developer can load
Backend routing, and a Backend-only developer can load Frontend routing. A
self-declared role would not fail closed because it would not prove current
GitHub Team membership.

## Chosen approach

Reuse the installed `gh` and `jq` dependencies to resolve exact membership in
the `beroka-vn/frontend` and `beroka-vn/backend` GitHub Teams. Store one
validated role in user scope, apply it to Backend and Frontend repository
contexts, and revalidate membership immediately before every external-write
preflight.

This keeps role enforcement inside the existing POSIX CLI. It adds no service,
daemon, dependency, wildcard routing, or self-declaration path.

## Rejected approaches

- A new server or GitHub App enforcement proxy would centralize the gate but
  would add deployment, authentication, and availability scope not required by
  Issue #29.
- Inferring role from repository access would confuse direct repository access
  with exact Team membership and would not satisfy the approved eligibility
  rule.
- Trusting an edited local role file or instruction-only policy would permit
  role escalation and would not fail closed before writes.

## User-scoped role

The CLI stores the selected role in
`${XDG_CONFIG_HOME:-$HOME/.config}/beroka-ai-governance/github-role`.
The file contains exactly one of:

```text
FE
BE
FULL_STACK
```

The file uses the package's existing safe user-path and regular-file checks.
Malformed, missing, or symlinked state returns `GITHUB_ROLE_REQUIRED`.
Uninstall removes the managed role file.

Role selection occurs during bootstrap after global connector setup:

1. Require healthy GitHub CLI authentication.
2. Query `gh api --paginate /user/teams`.
3. Match only team slug `frontend` or `backend` whose organization login is
   exactly `beroka-vn`.
4. Select `FE` automatically for Frontend-only membership.
5. Select `BE` automatically for Backend-only membership.
6. If both memberships exist, reuse an eligible stored role. Otherwise prompt
   once for `FE`, `BE`, or `Full-stack`; never default to Full-stack.
7. In non-interactive mode, dual membership without an eligible stored choice
   returns `GITHUB_ROLE_SELECTION_REQUIRED`.
8. Membership in neither team returns `GITHUB_ROLE_REQUIRED`.
9. An API, authentication, or response-validation failure returns
   `GITHUB_ROLE_UNAVAILABLE` or the existing `GITHUB_AUTH_REQUIRED` result.

Global Cursor MCP setup remains independent of role resolution. A role failure
does not remove or corrupt a healthy global connector.

## Repository scope

`context` and `doctor` read the stored role without a network request so
governance instructions remain available offline.

Role scope applies only to routed Backend and Frontend profiles:

| Stored role | Backend profile | Frontend profile |
| --- | --- | --- |
| `FE` | `ROLE_SCOPE_DENIED` | allowed |
| `BE` | allowed | `ROLE_SCOPE_DENIED` |
| `FULL_STACK` | allowed | allowed |

Standalone profiles keep their existing behavior. A denied context emits no
Backend/Frontend Jira, Confluence, or integration routing details.

Every preflight re-queries GitHub Teams before any connector login, OAuth
prompt, or external write is allowed. The stored role must still be eligible:

- `FE` requires current Frontend membership;
- `BE` requires current Backend membership;
- `FULL_STACK` requires both memberships.

Missing or stale eligibility returns `GITHUB_ROLE_REQUIRED` with bootstrap
remediation. A repository/profile mismatch returns `ROLE_SCOPE_DENIED`.
Cross-repository writes remain `explicit-only` and keep their existing
`ROUTING_REQUIRED` gate.

## Canonical repositories and transition aliases

`v1.0.4` adds canonical catalog records and integration inventory entries for:

```text
beroka-vn/Beroka_Backend
beroka-vn/Beroka_Frontend
```

The release retains these two published `v1.0.3` slugs as deprecated aliases
for the transition release only:

```text
cuongngo1801-beroka/Beroka_Backend
cuongngo1801-beroka/Beroka_Frontend
```

Alias records reuse the same Backend or Frontend routing values and therefore
receive the same role checks. Active README, handbook, governance, workflow,
template, and runtime documentation uses only `beroka-vn` URLs. Historical
plans and immutable releases remain unchanged.

The release test requires both aliases when `VERSION=v1.0.4` and rejects them
for later source versions. This makes the next version bump fail until the
transition aliases are removed.

## Failure behavior

- GitHub redirects never authorize routing; only exact release catalog records
  do.
- Unknown repositories remain `ROUTING_REQUIRED`.
- Team API failures never fall back to a stored or self-declared role.
- A missing role never defaults to Full-stack.
- A role mismatch fails before printing target routing or passing preflight.
- Role validation does not broaden Jira, Confluence, repository, counterpart,
  or cross-repository authority.
- Existing release-integrity, client-enrollment, connector, capability, and
  OAuth gates remain unchanged.

## Verification

The shell suite uses the existing fake `gh` boundary and real CLI commands.
Regression coverage includes:

- canonical Backend and Frontend routing;
- both `v1.0.3` deprecated aliases in `v1.0.4`;
- automatic FE-only and BE-only selection;
- dual membership with each explicit choice and no Full-stack default;
- neither-team, malformed API, missing role, and stale role failures;
- FE-to-Backend and BE-to-Frontend `ROLE_SCOPE_DENIED`;
- Full-stack access to both profiles while cross-repository writes stay
  blocked;
- offline `context` using a stored eligible role;
- preflight membership revalidation before connector or OAuth activity;
- active documentation containing only organization URLs;
- a version-aware gate that forces alias removal after `v1.0.4`.

The complete syntax, bootstrap, connector, documentation, launcher, release,
routing, and smoke suites must pass before review.

## Release scope

- Prepare version `v1.0.4` from the exact reviewed Issue #29 branch.
- Comment on Issue #29 with the confirmed `v1.0.3` evidence, design/plan links,
  regression results, and pull request.
- Do not combine Issue #30 or Issue #31 with this release.
- Merge only after explicit human confirmation of the exact pull request and
  reviewed commit.
- Create an annotated `v1.0.4` tag and GitHub Release only from the verified
  merge commit, without changing the immutable `v1.0.0` through `v1.0.3`
  releases.
