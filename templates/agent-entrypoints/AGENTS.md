<!-- BEROKA-GOVERNANCE:START -->
## Beroka AI Governance

This repository uses a pinned central governance release. Before Jira, GitHub,
Confluence, planning, or implementation work, run:

```bash
beroka-governance context "$PWD"
```

Follow the returned routing and load only the required document or template with
`beroka-governance show`. If validation does not return `Result: PASS`, stop the
dependent scope and report the exact governance result.

Repository-specific instructions may narrow central governance. They must not
broaden authority or bypass a central stop condition.
<!-- BEROKA-GOVERNANCE:END -->
