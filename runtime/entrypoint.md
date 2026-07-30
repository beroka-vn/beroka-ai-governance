# Beroka Team Development AI Workflow

The rules emitted by `beroka-governance context` are authoritative for this
repository session. Read the exact assigned issue and repository-local rules
before acting. If no exact central catalog record exists, context remains
source-only and loads the general rules plus the standalone profile.
After context compaction, a session resume, or a new chat, rerun
`beroka-governance context "$PWD"` before the next governed action. Never rely
on governance details preserved only in a conversation summary. In-progress
source work need not be discarded, but governance must be rehydrated before the
next planning, implementation, or external action. Rerun context when the IDE workspace or current Git repository changes, another repository enters scope,
or the plan becomes shared/full-stack. Classify the work first and run context
for every exact target repository; never infer a target from the open
workspace. Run a fresh
operation-specific preflight immediately before every external write; never
reuse a result from before compaction.
Run `beroka-governance preflight REPO --client CLIENT --operation OPERATION`
immediately before every routing-dependent external write. The selected client
owns OAuth. The verified active release's Central repository catalog is the
sole routing source, and preflight resolves its exact record before any OAuth
prompt. Catalog additions or routing changes require an explicitly
authorized governance-repository task; do not create, commit, or push them
in an application repository. Current-repository source, branch, commit, push,
Issue, and pull-request work does not require Atlassian OAuth.
