<!-- BEROKA-GOVERNANCE:START -->
## Beroka AI Governance

In a Git repository, before Jira, GitHub, Confluence, planning, or
implementation work, run `beroka-governance context "$PWD"`. Apply Beroka
governance only when it does not return `Result: NOT_GOVERNED`.

Rerun after session resume or context compaction, when the current Git repository or workspace changes,
when another repository enters scope, or when a plan becomes shared/full-stack.
Run it for every exact target repository.
<!-- BEROKA-GOVERNANCE:END -->
