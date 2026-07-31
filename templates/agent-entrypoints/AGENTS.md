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

Task, issue, and pull request work defaults to English unless the user
explicitly requests another language.

If a non-interactive preflight returns `ATLASSIAN_AUTH_REQUIRED`, stop the
dependent external write. In an interactive terminal, run
`codex mcp login atlassian`, stream the producer output so the user receives
the one-time login URL, wait for the producer command to complete, and never
synthesize, parse, persist, copy, or place that URL or credentials in an
issue, commit, or durable log. Then rerun a fresh operation-specific preflight
and continue only when it returns `Result: PASS`.

Repository-specific instructions may narrow central governance. They must not
broaden authority or bypass a central stop condition.
<!-- BEROKA-GOVERNANCE:END -->
