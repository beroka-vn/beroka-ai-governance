# Codex Inventory and GitHub Close Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live Codex Jira and Confluence preflights accept validated overlapping inventories, then require agents to reconcile a closed GitHub Issue to Jira `In Review` and exact Confluence documentation without advancing Jira to `Done`.

**Architecture:** Validate the direct Atlassian and reviewed Codex Apps tool sets independently, then set-union their canonical names so cross-record corroboration is not treated as ambiguity. Preserve partial-page state so exact presence can authorize while absence cannot. Express the close follow-up in the existing shared governance rules and their published copies; no listener or new runtime component is added.

**Tech Stack:** POSIX shell, `awk`, `jq`, existing shell test harness, Markdown governance rules.

**Spec:** `docs/superpowers/specs/2026-08-24-codex-inventory-and-close-lifecycle-design.md`

## Global Constraints

- Technical artifacts remain in English.
- No new dependency, daemon, webhook, credential, configuration value, or capability alias.
- Only exact reviewed aliases from the optional single `codex_apps` record are accepted.
- Malformed or duplicate names within one record remain blocked.
- A non-null pagination cursor cannot make missing tools authoritative.
- Every Jira or Confluence write still requires its own fresh operation-specific preflight.
- Missing or ambiguous Confluence context must be asked of the user, never guessed.
- Documentation readback leaves Jira in `In Review`; no automatic transition to `Done`.

---

### Task 1: Resolve overlapping Codex inventories

**Files:**
- Modify: `tests/routing.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: one `mcpServerStatus/list` response containing the required single `atlassian` record, an optional single `codex_apps` record, and optional `result.nextCursor`.
- Produces: `CAPABILITY_INVENTORY` as unique canonical names, `CAPABILITY_INVENTORY_FORMAT=json`, and `CAPABILITY_INVENTORY_COMPLETE=1` only when `nextCursor` is absent or null.
- Produces helper: `codex_inventory_page_complete()`, stdin JSON-RPC response to shell success for a terminal page and failure otherwise.

- [ ] **Step 1: Add the populated/populated overlap fixture**

Add a `healthy-codex-apps-overlap` case beside `healthy-codex-apps-split-jira` in the fake Codex app-server. The direct record contains the existing `healthy-all` Jira and Confluence tools. The Codex Apps record contains the six existing reviewed `atlassian_rovo.*` Jira aliases:

```sh
healthy-codex-apps-overlap)
  printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{},"updateConfluencePage":{}},"authStatus":"oAuth"},{"name":"codex_apps","tools":{"atlassian_rovo.createJiraIssue":{},"atlassian_rovo.getAccessibleAtlassianResources":{},"atlassian_rovo.getJiraIssue":{},"atlassian_rovo.getJiraIssueTypeMetaWithFields":{},"atlassian_rovo.getJiraProjectIssueTypesMetadata":{},"atlassian_rovo.searchJiraIssuesUsingJql":{}},"authStatus":"bearerToken"}],"nextCursor":null}}'
  ;;
```

Add assertions after the existing split-Jira case:

```sh
printf '%s\n' healthy-codex-apps-overlap \
  >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: PASS'
```

After `page_config` is published, run target-bound Confluence preflight with the same fixture and assert `SUPPORTED`, `COMPLETE`, and `PASS`.

- [ ] **Step 2: Run the overlap test and verify RED**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL in `healthy-codex-apps-overlap`; the canonical overlap currently makes runtime inventory unavailable.

- [ ] **Step 3: Canonicalize each trusted record before the union**

In the Codex arm of `connector_inventory()`, replace the combined duplicate-sensitive canonicalization with independent validation and a unique union:

```sh
ci_tools=$(printf '%s\n' "$ci_record" |
  json_top_level_tools |
  codex_canonical_tool_names) || return 1
ci_apps_record=$(printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
  codex_atlassian_record codex_apps optional) || return 1
ci_apps_tools=
if [ -n "$ci_apps_record" ]; then
  ci_apps_tools=$(printf '%s\n' "$ci_apps_record" |
    json_top_level_tools tools |
    codex_canonical_tool_names apps-only) || return 1
fi
CAPABILITY_INVENTORY=$({
  [ -z "$ci_tools" ] || printf '%s\n' "$ci_tools"
  [ -z "$ci_apps_tools" ] || printf '%s\n' "$ci_apps_tools"
} | LC_ALL=C sort -u) || return 1
CAPABILITY_INVENTORY_FORMAT=json
```

Do not change `codex_canonical_tool_names`; its per-record duplicate rejection protects the existing ambiguous-alias test.

- [ ] **Step 4: Run routing tests and verify GREEN for overlap and existing negatives**

Run:

```bash
sh tests/routing.sh
```

Expected: PASS, including `healthy-codex-apps-ambiguous`, malformed, near-match, cross-provider, and unreviewed-alias negatives.

- [ ] **Step 5: Add a partial-page absence regression and verify RED**

Add a `partial-codex-apps-read-only` fixture with authenticated records, reviewed read aliases, and `"nextCursor":"page-2"`. Assert Jira preflight is `UNKNOWN`, is not `UNSUPPORTED`, and does not pass:

```sh
printf '%s\n' partial-codex-apps-read-only \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'partial Codex inventory authorized Jira write'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_not_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
```

Run `sh tests/routing.sh`.

Expected: FAIL because the current adapter marks every parsed response complete and reports authoritative absence.

- [ ] **Step 6: Preserve partial-page evidence without authorizing absence**

Add immediately before `connector_inventory()`:

```sh
codex_inventory_page_complete() {
  jq -e -s '
    length == 1 and
    (.[0] | type == "object" and .id == 1 and
      (.result | type == "object") and
      ((.result.nextCursor? // null) == null))
  ' >/dev/null 2>&1
}
```

In the Codex arm of `connector_inventory()`, set completeness after building the validated inventory:

```sh
if printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
   codex_inventory_page_complete
then
  CAPABILITY_INVENTORY_COMPLETE=1
fi
```

Leave the initial value at zero. In `resolve_provider_capability()`, distinguish a present partial inventory from clients with no runtime inventory:

```sh
connector_inventory "$rpc_client" || return 0
if [ -n "$CAPABILITY_INVENTORY_FORMAT" ]; then
  if inventory_has_required_tools; then
    :
  elif [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
    CAPABILITY_INVENTORY_STATE=COMPLETE
    CAPABILITY_STATE=UNSUPPORTED
    CAPABILITY_EVIDENCE_SOURCE=RUNTIME_INVENTORY
    return 0
  else
    return 0
  fi
fi
if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
  CAPABILITY_INVENTORY_STATE=COMPLETE
fi
CAPABILITY_STATE=SUPPORTED
CAPABILITY_EVIDENCE_SOURCE=PROVIDER_CONTRACT
```

This preserves provider-contract behavior for Claude, which has no inventory format, while preventing a partial Codex page with missing tools from authorizing or proving absence.

- [ ] **Step 7: Verify the complete routing matrix**

Run:

```bash
sh -n bin/beroka-governance
sh -n tests/routing.sh
sh tests/routing.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 8: Commit the inventory fix**

```bash
git add bin/beroka-governance tests/routing.sh
git commit -m "fix: accept corroborating Codex inventories"
```

---

### Task 2: Require the GitHub-close Jira and Confluence follow-up

**Files:**
- Modify: `tests/documentation-architecture.sh`
- Modify: `runtime/rules/work-items.md`
- Modify: `runtime/integrations/beroka-be-fe.md`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `templates/jira-confluence.md`

**Interfaces:**
- Consumes: an agent closing, or observing during completion work that it just closed, the current primary GitHub Issue.
- Produces: an ordered instruction contract: exact linked Jira resolution, assignee verification, fresh `jira-write` preflight, idempotent `In Review`, exact Confluence ID or user clarification, target-bound preflight, update, readback, and Jira remaining `In Review`.

- [ ] **Step 1: Add lifecycle documentation-contract assertions**

In `tests/documentation-architecture.sh`, add exact assertions for the shared rule and reject the old automatic Done rule across every published copy:

```sh
for file in governance.md workflow.md runtime/rules/work-items.md \
  runtime/integrations/beroka-be-fe.md templates/jira-confluence.md; do
  require_text "$file" 'closes the current primary GitHub Issue'
  require_text "$file" 'exact linked Jira item'
  require_text "$file" 'already in `In Review`'
  require_text "$file" 'exact Confluence content ID'
  require_text "$file" 'ask the user'
  require_text "$file" 'documentation readback'
  require_text "$file" 'remains in `In Review`'
  reject_text "$file" 'In Review -> Done'
done
```

- [ ] **Step 2: Run the documentation test and verify RED**

Run:

```bash
sh tests/documentation-architecture.sh
```

Expected: FAIL because the close-triggered workflow is absent and all five files still contain the old automatic Done transition.

- [ ] **Step 3: Replace the lifecycle paragraph in every published copy**

Use the existing prose style in each file, preserving surrounding role and cross-team rules. The normative content must state:

```markdown
When an agent closes the current primary GitHub Issue, or observes during
completion work that it has just been closed, it resolves the exact linked Jira
item, verifies the authenticated account against the current assignee, runs a
fresh `jira-write` preflight, and transitions the item to `In Review`; an item
already in `In Review` is idempotently complete. It then resolves related
documentation only by exact Confluence content ID. If the page, parent, or
required change is missing or ambiguous, ask the user and wait. Otherwise run
a fresh target-bound Confluence preflight, update the documentation, and read
it back. After documentation readback Jira remains in `In Review`; do not move
it to `Done` automatically. Report a blocked Jira or Confluence step separately
and do not reopen the GitHub Issue.
```

Keep `To Do -> In Progress` when accepted work starts and `In Progress -> In Review` when a human marks the provider PR ready. The close follow-up is idempotent when that earlier transition already occurred.

- [ ] **Step 4: Verify the lifecycle contract and context rendering**

Run:

```bash
sh tests/documentation-architecture.sh
bin/beroka-governance context "$PWD"
git diff --check
```

Expected: the test exits 0; rendered context contains the close follow-up and contains no `In Review -> Done` rule.

- [ ] **Step 5: Commit the lifecycle rule**

```bash
git add tests/documentation-architecture.sh runtime/rules/work-items.md \
  runtime/integrations/beroka-be-fe.md governance.md workflow.md \
  templates/jira-confluence.md
git commit -m "feat: require post-close Jira and docs follow-up"
```

---

### Task 3: Verify the integrated change

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: Tasks 1 and 2 commits.
- Produces: fresh local-suite and live Codex preflight evidence for issue #77.

- [ ] **Step 1: Run the full repository suite**

Run:

```bash
for test_file in tests/*.sh; do sh "$test_file"; done
git diff --check
git status --short
```

Expected: every test exits 0, the diff check exits 0, and the working tree is clean.

- [ ] **Step 2: Rehydrate Backend governance before live qualification**

Run:

```bash
beroka-governance context /home/cuongngo/Beroka_Backend
```

Expected: repository `beroka-vn/Beroka_Backend`, routing `ROUTING_ACTIVE`, Jira project `BB`, and Confluence root content `65962274`.

- [ ] **Step 3: Run live source-branch preflights**

Run:

```bash
bin/beroka-governance preflight /home/cuongngo/Beroka_Backend \
  --client codex --operation jira-write --non-interactive
bin/beroka-governance preflight /home/cuongngo/Beroka_Backend \
  --client codex --operation confluence-write --non-interactive \
  --confluence-action create --target-content-id new \
  --expected-parent-id 65962274
```

Expected for both: `Capability state: SUPPORTED`, `Runtime inventory: COMPLETE`, and `Result: PASS`. These commands perform no Jira or Confluence write.

- [ ] **Step 4: Review the final diff against the spec**

Run:

```bash
git diff origin/main...HEAD --check
git log --oneline --decorate origin/main..HEAD
git status --short
```

Confirm every spec requirement has code or documentation coverage, no raw tool inventory is printed, and no external record was changed.
