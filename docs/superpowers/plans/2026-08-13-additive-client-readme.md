# Additive Client Enrollment README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shorten the README and document how to add a second supported client while preserving the first.

**Architecture:** Keep the README as the concise entry point and retain the existing launcher commands as the only installation interface. Move detailed release history, connector behavior, and routing edge cases out of README assertions because `handbook.md` and `PACKAGE-DESIGN.md` already own them.

**Tech Stack:** Markdown, POSIX shell documentation assertions.

## Global Constraints

- Enrollment is additive for `codex`, `claude`, and `cursor`.
- The Codex-to-Claude example reruns bootstrap with `--client claude` and without `--upgrade`.
- Existing enrolled clients remain enabled.
- Do not change runtime behavior, `VERSION`, tags, releases, or GitHub releases.

---

### Task 1: Protect the concise enrollment contract

**Files:**
- Modify: `tests/documentation-architecture.sh`
- Modify: `tests/connectors.sh`
- Modify: `tests/release.sh`

**Interfaces:**
- Consumes: README headings and literal user-facing enrollment statements.
- Produces: assertions for the additive command, preservation semantics, and concise README boundary.

- [x] **Step 1: Replace obsolete README assertions**

Require `## Add another client`, `sh -s -- --client claude`, a statement that Codex remains enrolled, and a statement that `--upgrade` is not used to add a client. Reject the removed `### v1.0.11 release` and `### v1.0.11 upgrade` headings. Keep exact executable launcher assertions for Quick start, Upgrade, and Automation / CI.

- [x] **Step 2: Verify the assertions fail against the old README**

Run: `sh tests/documentation-architecture.sh && sh tests/connectors.sh && sh tests/release.sh`

Expected: FAIL because `## Add another client` is absent.

### Task 2: Rewrite README as the concise entry point

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the existing canonical launcher blocks and links to `handbook.md` and `PACKAGE-DESIGN.md`.
- Produces: short setup, additive enrollment, operation, lifecycle, CI, workflow, and document-index guidance.

- [x] **Step 1: Remove duplicated detail**

Delete version-specific release history, detailed OAuth state-machine prose, Cursor implementation internals, and catalog-routing edge cases that are already documented in the handbook or package design.

- [x] **Step 2: Add the additive Codex-to-Claude example**

Reuse the canonical launcher with `sh -s -- --client claude`, state that both clients remain enrolled, and explicitly say not to pass `--upgrade` when adding a client to the active release.

- [x] **Step 3: Run focused documentation tests**

Run: `sh tests/documentation-architecture.sh && sh tests/connectors.sh && sh tests/release.sh`

Expected: all three scripts print PASS and exit 0.

- [x] **Step 4: Run the full repository gate**

Run: `sh -n bin/beroka-governance tests/pty.shlib tests/*.sh && for test_file in tests/*.sh; do sh "$test_file"; done && git diff --check`

Expected: every test exits 0 and the diff check is clean.

- [x] **Step 5: Commit the implementation**

```bash
git add README.md tests/documentation-architecture.sh tests/connectors.sh tests/release.sh docs/superpowers/plans/2026-08-13-additive-client-readme.md
git commit -m "docs: clarify additive client enrollment"
```
