<!-- BEROKA-GOVERNANCE:START -->
## Beroka AI Governance

This repository uses a pinned central governance release. Before Jira, GitHub,
Confluence, planning, or implementation work, run:

```bash
beroka-governance context "$PWD"
```

After context compaction, a session resume, or a new chat, rerun
`beroka-governance context "$PWD"` before the next governed action. Never rely
on governance details preserved only in a conversation summary. In-progress
source work need not be discarded, but governance must be rehydrated before the
next planning, implementation, or external action. Run a fresh
operation-specific preflight immediately before every external write; never
reuse a result from before compaction.

Follow the returned routing and load only the required document or template with
`beroka-governance show`. If validation does not return `Result: PASS`, stop the
dependent scope and report the exact governance result.

Repository-specific instructions may narrow central governance. They must not
broaden authority or bypass a central stop condition.
<!-- BEROKA-GOVERNANCE:END -->
