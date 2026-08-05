# Confluence Target Bootstrap Design

**Date:** 2026-08-05
**Issue:** [GitHub #51](https://github.com/beroka-vn/beroka-ai-governance/issues/51)
**Status:** Approved for implementation
**Follow-up to:** #44 target-bound Confluence preflight

## Goal

Give agents a deterministic, fail-closed path from a deny-only or legacy-only
Confluence inventory to a reviewed ACTIVE folder plus known Registry content ID,
without guessing IDs or weakening target-bound preflight.

## Phases

1. **Discovery (read-only)** — `confluence-discover` classifies the reviewed
   inventory and catalog root. It does not call Atlassian.
2. **Authorized bootstrap** — `confluence-bootstrap-plan` emits exact create
   payloads. A human must confirm. The agent creates via MCP. Then
   `confluence-bootstrap-capture` and `confluence-bootstrap-verify` validate
   returned IDs and parent read-back.
3. **Ordinary documentation update** — after a reviewed inventory PR lands
   ACTIVE folder rows (and Registry IDs are known for page rows), use ordinary
   target-bound `confluence-write`.

## Non-goals

- CLI does not call Atlassian APIs.
- CLI does not mutate the installed release inventory.
- Legacy folders remain non-writable parents.
- No title-similarity resolution.

## Results

| Result | Meaning |
| --- | --- |
| `DISCOVERY_COMPLETE` | Inventory classified; `Next:` names the following command |
| `BOOTSTRAP_PLAN` | Exact folder and Registry create plan emitted |
| `BOOTSTRAP_CAPTURED` | Returned IDs staged under user state |
| `BOOTSTRAP_VERIFIED` | Read-back matched; ACTIVE folder TSV ready for governance PR |
| `INVENTORY_UPDATE_REQUIRED` | Reviewed PR must append the emitted ACTIVE folder row |
| `FOLDER_CREATION_REQUIRED` | Includes `Remediation:` discover then bootstrap-plan |
| `DOC_HIERARCHY_FAILED` | Parent read-back ≠ catalog root |
| `MAPPING_CONFLICT` | Captured ID collides with LEGACY/DRIFTED/ACTIVE or titles mismatch |
