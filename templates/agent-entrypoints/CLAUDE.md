<!-- BEROKA-GOVERNANCE:START -->
## Beroka AI Governance

This workstation uses verified Beroka governance. In a Git repository, before
Jira, GitHub, Confluence, planning, or implementation work, run:

```bash
beroka-governance context "$PWD"
```

After context compaction, session resume, or a new chat, rerun context before
the next governed action. Also rerun context when the IDE workspace or current Git repository changes, another repository enters scope, or a plan becomes
shared/full-stack. Run context for every exact target repository. Run a fresh
operation-specific preflight immediately before every external write. Never
rely on governance details preserved only in conversation history.

Technical artifacts default to English; chat language does not select artifact language.
Use another language only when the user explicitly supplies
`Work-item language: <language>` for the current generation.

If a non-interactive preflight returns `ATLASSIAN_AUTH_REQUIRED`, stop the
dependent external write. In an interactive terminal or PTY, run
`claude mcp login atlassian --no-browser` and stream the opaque producer
output unchanged so the user receives its one-time login URL. Never
synthesize, parse, persist, copy, or place that URL or credentials in an
issue, commit, or durable log. Wait for the producer command to complete.
Then rerun a fresh operation-specific preflight and continue only when it
returns `Result: PASS`.

Repository-specific instructions may narrow central governance. They must not
broaden authority or bypass a central stop condition.

Ordinary Cursor Confluence create/update/move is allow-by-default unless the
target is `UNACTIVATED` and returns `DOCS_UNACTIVATED`. Cursor is the only
trusted Confluence create/update boundary in this release. Codex and Claude Confluence create/update require a trusted actual-body boundary and must stop
with `CLIENT_BODY_GATE_REQUIRED`; do not treat a temporary or caller-provided
body file as proof of the Atlassian request. Jira operations, Confluence moves,
and capability-only readback retain their existing governed paths. A cross-team
handoff is a self-contained Jira-and-Confluence-only contract: use Cursor's
configured Atlassian MCP `createConfluencePage` or `updateConfluencePage` tool
with the exact body and reviewed ACTIVE Folder. Its in-process Cursor hook
stages the actual tool-call body and runs `confluence-handoff-write`; a
standalone preflight cannot prove the Atlassian request. A fresh
`beroka-governance preflight REPO --client CLIENT --operation confluence-handoff-verify --non-interactive --confluence-action update --target-content-id ID --expected-parent-id ID --handoff-body-file FILE` proves read capability only. Without trusted client post-tool write/read results, report unverified and do not report `READY_FOR_FE`.
Use optional `confluence-discover` / `confluence-bootstrap-*` only as hierarchy
guidance, never as a write gate.
Create Jira items with Atlassian MCP `createJiraIssue` using official fields
(`projectKey`, `issueTypeName`, `parent`, `assignee_account_id`,
`additional_fields.priority.name`) and put `Work-item language: English` plus
`GitHub: <url|N/A>` in `description`. On FULL_STACK Backend+Frontend multi-root,
name exactly one of BB/BF via `projectKey` or parent/epic key; do not ask the
user to close a workspace folder. On `WORK_ITEM_TEMPLATE_REQUIRED`, read
`Missing:` from the hook message, fix once, and retry — do not surface raw
governance codes to the user.
Before a Jira update, compare the authenticated and current-assignee Atlassian
account IDs; mismatch or unassigned returns `ASSIGNEE_CONFIRMATION_REQUIRED`.
Never place opposite-team private GitHub links in cross-team Jira or handoff
text; use the exact accessible Confluence page.
<!-- BEROKA-GOVERNANCE:END -->
