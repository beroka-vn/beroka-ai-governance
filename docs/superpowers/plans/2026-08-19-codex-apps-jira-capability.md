# Codex Apps Jira Capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex Jira-write preflight recognize the reviewed Codex Apps Atlassian Rovo tool identities without weakening exact capability checks.

**Architecture:** Canonicalize only the six reviewed namespaced Jira tool identities emitted by Codex Apps immediately after parsing the selected Atlassian server's tool map. Preserve unknown names unchanged and reject two runtime names that map to the same canonical tool, so required-tool checks remain exact and fail closed.

**Tech Stack:** POSIX shell, AWK, the existing shell integration test harness.

**Spec:** GitHub issue `beroka-vn/beroka-ai-governance#74`.

## Global Constraints

- Work only in `beroka-vn/beroka-ai-governance` and issue #74 scope.
- Preserve exact provider, authentication, server-boundary, and required-tool checks.
- Do not log or persist OAuth URLs, credentials, tokens, or session secrets.
- Add no dependency or abstraction beyond the existing shell parser pipeline.

---

### Task 1: Canonicalize Reviewed Codex Apps Jira Tools

**Files:**
- Modify: `tests/routing.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: newline-delimited, parser-validated top-level tool names from `json_top_level_tools`.
- Produces: newline-delimited canonical tool names consumed by `inventory_has_required_tools`; duplicate canonical identities return non-zero.

- [ ] **Step 1: Add the failing runtime fixtures and assertions**

Add a complete Codex Apps Atlassian Rovo fixture using these exact identities:

```text
mcp__codex_apps__atlassian_rovo_createjiraissue
mcp__codex_apps__atlassian_rovo_getaccessibleatla_4b5564c6c5e4
mcp__codex_apps__atlassian_rovo_getjiraissue
mcp__codex_apps__atlassian_rovo_getjiraissuetypemetawithfields
mcp__codex_apps__atlassian_rovo_getjiraprojectiss_ccce75cac970
mcp__codex_apps__atlassian_rovo_searchjiraissuesusingjql
```

Assert that Doctor reports authenticated connector PASS while `jira-write` preflight reports `SUPPORTED`, `PROVIDER_CONTRACT`, `COMPLETE`, and `PASS`. Add read-only, similar-name, cross-provider, and duplicate-canonical fixtures that remain blocked.

- [ ] **Step 2: Run the regression test and verify RED**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL because the complete namespaced fixture resolves `UNSUPPORTED / RUNTIME_INVENTORY` before canonicalization exists.

- [ ] **Step 3: Add the minimal exact canonicalization**

Add one AWK filter beside `json_top_level_tools` that maps only the six reviewed identities to:

```text
createJiraIssue
getAccessibleAtlassianResources
getJiraIssue
getJiraIssueTypeMetaWithFields
getJiraProjectIssueTypesMetadata
searchJiraIssuesUsingJql
```

Keep every unrecognized identity unchanged and return non-zero if two input identities map to the same canonical name. Pipe only the Codex inventory through this filter.

- [ ] **Step 4: Run focused and full verification**

Run:

```bash
sh tests/routing.sh
sh tests/connectors.sh
sh tests/release.sh
```

Expected: each command prints its PASS marker and exits 0.

- [ ] **Step 5: Inspect the final diff**

Run:

```bash
git diff --check
git diff --stat origin/main...HEAD
git status --short --branch
```

Expected: no whitespace errors; only the plan, runtime, and routing test files are changed.
