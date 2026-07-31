# Cross-Team Jira Intake Design

**Date:** 2026-07-31
**Issue:** [GitHub #40](https://github.com/beroka-vn/beroka-ai-governance/issues/40)
**Status:** Ready for review
**Target release:** `v1.0.5`

## Goal

Allow a verified Frontend requester to submit a constrained Backend intake
item, and a verified Backend requester to submit the symmetric Frontend item,
without granting either role general authority over the receiving repository.

## Authorization Boundary

The existing `jira-write` operation and `ROLE_SCOPE_DENIED` behavior remain
unchanged. A new `jira-intake-write` preflight is the only cross-team intake
path.

The operation:

1. starts from the requesting team's exact routed repository;
2. verifies the stored GitHub role and live Team membership against that source
   repository;
3. resolves the one opposite-team repository and Jira project from the active,
   exact `beroka-be-fe` integration inventory;
4. requires `CROSS_REPO_POLICY=profile-controlled`, an explicit user write
   request, Jira create metadata, and duplicate search evidence;
5. returns the receiving Jira project and `jira-issue-write` capability; and
6. fails closed before OAuth or a write when the counterpart, profile,
   integration mapping, or intake workflow support is absent or ambiguous.

Standalone repositories, `explicit-only` routes, same-team targets, arbitrary
project keys, and general writes in the receiving project are not eligible.
This avoids weakening the repository role matrix or treating a GitHub role as
Jira administration authority.

## Intake Lifecycle

The requester creates only the intake record and remains reporter/requester.
The initial assignee is unassigned or an exactly configured receiving-team
triage owner. Sprint is unset, and requested priority is input rather than a
commitment.

The receiving team exclusively owns duplicate resolution, issue type, active
parent Epic, acceptance or rejection, final priority, Sprint, readiness, and
executor assignment. Requester and executor are distinct identities; no rule
reassigns receiving-team work to a cross-team requester.

Assignment alone never authorizes a GitHub Issue. A receiving-team agent may
create exactly one technical Issue in its own repository only after `Accepted`,
`Ready`, an assigned executor, Definition of Ready `PASS`, and a search proving
that no primary GitHub Issue already exists. The agent reads the Jira link and
GitHub ownership back before reporting `PASS`.

This is agent-driven at the next governed planning or execution action. No
daemon or event listener is introduced.

## Dependency Boundary

BB and BF keep separate Jira and GitHub records under same-project parents.
Provider work `Blocks` consumer work; non-blocking same-capability work
`Relates`. No item is cross-parented between Jira projects.

## Delivery

Add the intake operation to the existing preflight routing switch and reuse the
current role membership, connector, capability, and integration inventory
helpers. Add no new dependency or service.

Update `governance.md`, `workflow.md`, `runtime/rules/work-items.md`, and
`templates/jira-confluence.md` to separate requester/reporter from
executor/assignee and define both directions and the GitHub Issue gate.

Focused shell tests cover FE-to-BE and BE-to-FE success, unsupported mappings,
same-team and standalone rejection, unchanged ordinary `ROLE_SCOPE_DENIED`,
assignment-only rejection, requester reassignment rejection, and duplicate
GitHub Issue prevention.

Do not configure Jira workflows, create live BB/BF records, alter application
repositories, add runtime NLP, or change release metadata.

## Validation

- Routing tests prove the dedicated operation is narrow and the existing role
  matrix is unchanged.
- Documentation tests prove the symmetric lifecycle and requester/executor
  separation.
- The complete shell suite remains green.

