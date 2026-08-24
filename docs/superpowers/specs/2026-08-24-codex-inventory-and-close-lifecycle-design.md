# Codex Inventory and GitHub Close Lifecycle Design

**Issue:** beroka-vn/beroka-ai-governance#77  
**Work-item language:** English

## Goal

Restore operation-specific Jira and Confluence preflight for the live Codex
inventory shape without weakening exact capability checks, and make the agent
complete the Jira and Confluence follow-up whenever it closes the current
GitHub Issue.

## Root cause

Codex CLI 0.149.1 returns both an authenticated `atlassian` MCP record and a
`codex_apps` record. In the reproduced response, all 28 direct Atlassian tools
also appear as reviewed `atlassian_rovo.*` aliases in the Codex Apps record.
The v1.0.14 adapter canonicalizes both records together and rejects any
duplicate canonical name, so the valid overlap makes the complete inventory
unavailable. Issue #78 covered an empty direct record plus a populated Codex
Apps record, but not the live populated/populated shape.

## Inventory resolution

Keep the existing two exact trusted inputs:

- direct tool names from the single authenticated `atlassian` record;
- only reviewed exact Atlassian aliases from the optional single
  `codex_apps` record.

Validate and canonicalize each record independently. Reject duplicates within
either record because they are ambiguous. Merge the two validated sets as a
set, allowing the same canonical capability to appear once in each trusted
record. This overlap is corroborating evidence, not ambiguity.

All existing fail-closed behavior remains: malformed records, duplicate server
records, unreviewed aliases, near matches, cross-provider names,
authentication failure, unavailable inventory, and missing required tools
cannot authorize a write. A non-null pagination cursor prevents tool absence
from becoming authoritative `UNSUPPORTED`; exact required-tool presence may
still prove support. Diagnostics remain allowlist-only and must not print raw
inventory or tool names.

## GitHub close follow-up

This is an agent-driven workflow, not a webhook or background service. When an
agent closes the current primary GitHub Issue, or observes during completion
work that it has just been closed, it must continue in this order:

1. Resolve the exact linked Jira item from records already in scope.
2. Read the authenticated Atlassian account and current Jira assignee. Stop and
   request the required user confirmation on mismatch or an unassigned item.
3. Run a fresh `jira-write` preflight immediately before the Jira write and
   transition the item to `In Review`. Treat an item already in `In Review` as
   idempotently complete; do not transition it to `Done`.
4. Resolve related Confluence content only by an exact content ID from the
   linked records. If the required page, parent, or documentation change is
   missing or ambiguous, ask the user for the missing information and wait.
5. With an exact target and handoff markers, run a fresh target-bound
   Confluence preflight, update the documentation, and read it back.
6. Leave Jira in `In Review` after successful documentation readback and report
   the GitHub, Jira, and Confluence outcomes separately.

A failed Jira or Confluence step does not reopen the GitHub Issue and must not
be reported as complete. Existing routing, assignee, handoff-marker,
cross-team-link, and unactivated-document gates continue to apply.

## Documentation changes

Add the close follow-up to the shared work-item rules used by governed agents.
Replace the current automatic `In Review -> Done` rule with an explicit rule
that documentation readback leaves Jira in `In Review`; a later human-directed
transition may move it to `Done`.

No event listener, status daemon, new configuration, or new dependency is
introduced.

## Tests

- Add a routing regression fixture where direct Atlassian tools and reviewed
  Codex Apps aliases overlap, and require Jira and Confluence preflight PASS.
- Keep negative coverage for duplicates within one record, malformed names,
  unreviewed aliases, near matches, cross-provider names, missing tools,
  incomplete evidence, and authentication failures.
- Add documentation-contract assertions for close-triggered `In Review`, exact
  Confluence ID resolution, clarification on missing documentation context,
  readback, and remaining in `In Review`.
- Run the focused routing and documentation tests, then the full repository
  test suite.

## Non-goals

- Automatically transitioning Jira to `Done`.
- Reopening a closed GitHub Issue when an external follow-up is blocked.
- Adding webhook infrastructure or persistent credentials.
- Guessing Jira or Confluence mappings.
- Broadening the reviewed Codex Apps alias allowlist.
