# Beroka Team Development AI Workflow

Result: PASS

The current repository and governance release were validated by
`beroka-governance context`.

Before Jira, GitHub, Confluence, planning, or implementation work:

1. Read the repository rules and exact assigned issue first.
2. Run `beroka-governance show "$PWD" handbook` before provider setup or preflight.
3. Run `beroka-governance show "$PWD" governance` for authority, ownership, readiness, mapping, and stop conditions.
4. Run `beroka-governance show "$PWD" workflow` for the relevant lifecycle steps.
5. Load only the required template with `beroka-governance show "$PWD" template NAME`.

Never guess a Jira project, Epic, counterpart, assignee, Capability ID, Hub row,
documentation location, permission, repository, or contract version. A missing
or failed package/provider check blocks only the dependent scope and must never
be reported as PASS.
