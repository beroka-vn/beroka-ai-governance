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

The terminal live inventory later exposed the required Confluence operations
only in Codex Apps. The user explicitly authorized these three exact reviewed
dot-namespace aliases: `atlassian_rovo.createConfluencePage`,
`atlassian_rovo.getConfluencePage`, and
`atlassian_rovo.updateConfluencePage`.

## Inventory resolution

Keep the existing two exact trusted inputs:

- direct tool names from the single authenticated `atlassian` record;
- only reviewed exact Atlassian aliases from the optional single `codex_apps`
  record when its exact `authStatus` is `bearerToken`.

Validate and canonicalize each record independently. Reject duplicates within
either record because they are ambiguous. Merge the two validated sets as a
set, allowing the same canonical capability to appear once in each trusted
record. This overlap is corroborating evidence, not ambiguity.

The canonical allowlist includes only the three explicitly authorized
Confluence aliases above. It does not accept legacy, hashed, preview,
suffixed, or any other new aliases.

All existing fail-closed behavior remains: malformed records, duplicate server
records, unreviewed aliases, near matches, cross-provider names,
authentication failure, unavailable inventory, and missing required tools
cannot authorize a write. A Codex Apps record with missing, null, malformed,
unknown, unsupported, or `notLoggedIn` authentication cannot contribute tools.
A page is terminal only when `result.nextCursor` is absent or occurs exactly
once with the exact value `null`; any other value or duplicate cursor key
prevents tool absence from becoming authoritative `UNSUPPORTED`. Exact
required-tool presence may still prove support. Diagnostics remain
allowlist-only and must not print raw inventory or tool names.

## GitHub close follow-up

This is an agent-driven workflow, not a webhook or background service.
`Closes #<issue>` normally closes the GitHub Issue. If it remains open, an
agent may close it only after exact merge/link readback proves the delivered
commit and the close write is authorized. The follow-up begins only after the
automatic close or that authorized manual close, in this order:

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

Add the normative close follow-up to `runtime/rules/general.md`, which every
profile renders, and remove duplicate normative copies from the work-item and
BE/FE integration runtime sources. Keep explanatory copies in `governance.md`,
`workflow.md`, and `templates/jira-confluence.md`. Replace the current automatic
`In Review -> Done` rule with an explicit rule that documentation readback
leaves Jira in `In Review`; a later human-directed transition may move it to
`Done`. After success, report GitHub, Jira, and Confluence outcomes separately;
retain separate blocked-step reporting and never reopen the GitHub Issue.

No event listener, status daemon, new configuration, or new dependency is
introduced.

## Tests

- Add a routing regression fixture where direct Atlassian tools and reviewed
  Codex Apps aliases overlap, and require Jira and Confluence preflight PASS.
- Keep negative coverage for duplicates within one record, malformed names,
  unreviewed aliases, near matches, cross-provider names, missing tools,
  incomplete evidence, and authentication failures.
- Add Codex Apps authentication regressions for missing, unknown, and
  `notLoggedIn` states, plus pagination regressions for boolean false and
  duplicate cursor keys.
- Add documentation-contract assertions for close-triggered `In Review`, exact
  Confluence ID resolution, clarification on missing documentation context,
  readback, remaining in `In Review`, manual-close authority, and separate
  successful outcomes. Add context regressions for routed standalone and a
  single lifecycle copy in BE/FE context.
- Run the focused routing and documentation tests, then the full repository
  test suite.

## Non-goals

- Automatically transitioning Jira to `Done`.
- Reopening a closed GitHub Issue when an external follow-up is blocked.
- Adding webhook infrastructure or persistent credentials.
- Guessing Jira or Confluence mappings.
- Adding Codex Apps aliases beyond the three explicitly authorized Confluence
  aliases.
