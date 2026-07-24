# Beroka Team Development AI Workflow

The rules emitted by `beroka-governance context` are authoritative for this
repository session. Read the exact assigned issue and repository-local rules
before acting. Context may remain source-only while routing is unverified; it
loads only general rules plus the selected profile and integration profile.
Run `beroka-governance preflight REPO --client CLIENT --operation OPERATION`
immediately before every routing-dependent external write. The selected client
owns OAuth, and preflight verifies the freshly fetched default-branch routing
baseline before prompting for it. Pending local routing may be committed,
pushed, and reviewed, but cannot route Jira, Confluence, or cross-repository
writes. Current-repository source, branch, commit, push, Issue, and pull-request
work does not require Atlassian OAuth.
