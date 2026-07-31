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
<!-- BEROKA-GOVERNANCE:END -->
