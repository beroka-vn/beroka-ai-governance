# Frontend Repository

- The repository consumes exact published contract artifacts and versions. It
  uses a self-contained Confluence handoff snapshot for cross-team work and
  never requires access to Backend team-local repositories.
- Frontend `<Module> — Capability Index` pages link exact Backend Registry rows
  and content IDs. The Index remains a team-local navigation record; the
  consumer-facing Confluence handoff carries the complete public contract.
- Jira and Confluence writes remain inside the configured routing unless an
  active integration profile authorizes an exact counterpart.
- Frontend classification alone does not declare a Backend dependency.
