# Confluence Allow-by-Default + Release UNACTIVATED Design

**Date:** 2026-08-11
**Status:** Approved for implementation
**Replaces hard-deny path:** inventory PLANNED/ACTIVE gate + `confluence-folder-parent-write` UNKNOWN for ordinary creates

## Goal

Keep Backend Confluence as the FE source of truth and preserve traceability to
Jira and GitHub, without blocking ordinary documentation create/update/move.
Hard-lock only targets that a governance release explicitly marks `UNACTIVATED`.

## Policy

1. **Default writable.** Any page or folder not listed as `UNACTIVATED` in the
   pinned governance release inventory may be created, updated, or moved.
2. **UNACTIVATED is release-only.** Rows are hardcoded in
   `runtime/integrations/beroka-be-fe.confluence-targets` by a reviewed
   governance release. Agents and end-user sessions must never unactivate a
   target locally or via MCP/CLI.
3. **Handoff delta is mandatory** on create and update so FE can consume the
   change without rescanning a large canonical page:
   - Markers: `Jira: <KEY|URL>` and `GitHub: <URL|N/A>`
   - Delta form A: a section heading `## Handoff — <JiraKey>` (or `# Handoff —`)
     with this change’s summary
   - Delta form B: child page titled `Handoff — <JiraKey> — <date-or-slug>` plus
     body marker `Handoff form: child-page` and a link to the canonical page
4. **Hierarchy is guidance.** `LEGACY` / preferred Scope—Domain—Transport folders
   and `confluence-bootstrap-*` remain discoverability helpers. They do not
   hard-deny ordinary writes.
5. **Capability.** `create|move` use `confluence-page-parent-write` (provider
   SUPPORTED). Do not require `confluence-folder-parent-write` for ordinary
   writes.

## Deny results

| Result | When |
| --- | --- |
| `DOCS_UNACTIVATED` | Target content ID or parent ID matches an `UNACTIVATED` inventory row |
| `HANDOFF_DELTA_REQUIRED` | Cursor/MCP body missing Jira, GitHub, or handoff section/child-page evidence |
| `CONNECTOR_CAPABILITY_REQUIRED` | Only when the chosen capability is not SUPPORTED (should not apply to ordinary create after the flip) |
| `MAPPING_CONFLICT` | Structured IDs conflict when still supplied |

## Inventory

Add state `UNACTIVATED` for `page` or `folder` with a numeric `content-id`.
Existing `LEGACY` / `ACTIVE` / `PLANNED` / `DRIFTED` rows may remain for
discover and soft guidance. They are not write gates under this policy.

## Non-goals

- Session-side or agent-initiated unactivation
- Requiring Capability Registry IDs before the first page write
- Shipping `confluence-folder-parent-write` SUPPORTED without a separate pilot
