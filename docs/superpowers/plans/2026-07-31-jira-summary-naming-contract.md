# Jira Summary Naming Contract Implementation Plan

> **Issue:** [#39](https://github.com/beroka-vn/beroka-ai-governance/issues/39)
> **Design:** [Jira summary naming contract](../specs/2026-07-31-jira-summary-naming-contract-design.md)

**Goal:** Publish one exact instruction-driven Jira summary contract with
complete Frontend and Backend examples.

**Boundary:** Documentation and regression assertions only. No runtime parser,
dependency, Jira configuration, or release metadata change.

---

### Task 1: Add the failing contract assertions

**File:** `tests/documentation-architecture.sh`

1. Require the four exact formats in `runtime/rules/work-items.md`.
2. Require English sentence case, no trailing punctuation, and no Jira key or
   type prefix in the compact runtime rule.
3. Require all sixteen approved examples in
   `templates/jira-confluence.md`.
4. Run `sh tests/documentation-architecture.sh` and confirm it fails on the
   first missing contract assertion.

### Task 2: Publish the contract

**Files:**

- `runtime/rules/work-items.md`
- `governance.md`
- `workflow.md`
- `templates/jira-confluence.md`

1. Add the compact four-type contract and global naming rule to the runtime
   work-item rules.
2. Add the same authoritative formats to the durable Jira governance and
   workflow sections.
3. Replace Feature/Bug generic fallback guidance with an explicit Jira Summary
   Contract section containing all approved examples.
4. Keep existing metadata, duplicate, parent, ownership, and readback rules
   unchanged.
5. Run `sh tests/documentation-architecture.sh` and confirm `PASS`.

### Task 3: Verify and commit

1. Run `git diff --check`.
2. Run every `tests/*.sh` script and record any unrelated or unverified result
   accurately.
3. Confirm `VERSION`, tags, and release metadata are unchanged.
4. Commit the tested implementation with:

   ```bash
   git commit -m "docs(governance): define Jira summary contracts"
   ```

