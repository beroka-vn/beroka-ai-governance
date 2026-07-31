# GitHub Role Whitespace Hotfix Design

Status: Approved

## Problem

Interactive bootstrap reads the GitHub role selection verbatim and compares it
with exact shell `case` patterns. An intended token such as
`  Full-stack  ` therefore returns `GITHUB_ROLE_SELECTION_REQUIRED` even when
the user belongs to both required GitHub Teams.

The role membership checks, canonical stored values, and fail-closed behavior
are correct. Only the interactive input boundary lacks normalization.

## Chosen approach

Immediately after the interactive `IFS= read -r` call, trim the complete
leading and trailing runs of POSIX `[[:space:]]` characters from the answer in
one normalization step. Pass that result to the existing role `case` statement
without any further transformation.

Keep the accepted input tokens exactly as they are:

- `FE` and `fe` store `FE`;
- `BE` and `be` store `BE`;
- `Full-stack`, `full-stack`, and `FULL_STACK` store `FULL_STACK`.

Whitespace-only input becomes empty and fails through the existing
`GITHUB_ROLE_SELECTION_REQUIRED` branch. Whitespace inside a token is
preserved, so internal-space variants remain invalid.

This change stays in `configure_github_role`; it adds no helper, dependency,
configuration, retry, or alternate input path.

## Rejected approaches

- Adding whitespace variants to the `case` patterns would be incomplete and
  duplicate validation rules.
- Lowercasing or otherwise canonicalizing the whole answer would accept new
  spellings beyond Issue #35.
- Changing global shell `IFS` or role-file loading would broaden the fix beyond
  the interactive input boundary.

## Failure and security behavior

Unknown, empty, whitespace-only, punctuation, spelling, and internal-space
variants continue to return `GITHUB_ROLE_SELECTION_REQUIRED`. Team membership
eligibility remains authoritative: the hotfix does not permit a role that the
existing GitHub Team checks reject.

Stored role values remain exactly `FE`, `BE`, or `FULL_STACK`. GitHub
authentication, Team discovery, repository routing, connector behavior, Jira
behavior, and external-write preflight ordering remain unchanged.

## Verification

Add the smallest regression coverage at the existing interactive bootstrap
boundary:

1. Observe the regression fail before implementation when
   `  Full-stack  ` is supplied for dual Team membership.
2. After implementation, prove the same input stores `FULL_STACK`.
3. Prove every existing accepted FE, BE, and Full-stack token remains valid.
4. Prove empty, whitespace-only, unknown, internal-space, and ineligible inputs
   remain blocked.

Run the complete release suite after the focused regression passes.

## Release scope

Target inclusion in patch release `v1.0.5`. This issue and implementation PR
must not update `VERSION`, supported-release documentation, launcher commands,
or release assertions. Prepare those release-only changes after Issue #35 and
Issue #36 are both merged at their exact reviewed commits.

Do not change GitHub Team discovery, stored role values, repository routing,
Jira behavior, connector behavior, application repositories, or immutable
earlier releases. Merge, tag, and GitHub Release publication remain outside
this design-writing step and require exact human confirmation at their
governed gates.
