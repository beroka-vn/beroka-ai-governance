# Backend–Frontend Integration

- BB and BF use separate project-local Jira items and exact verified links.
- A shared capability uses one verified mapping and one owning Integration Hub.
- Backend publishes the canonical contract artifact; Frontend consumes its
  exact version and does not reconstruct it from issue descriptions.
- Similar names produce candidates only and never authorize links or writes.
- Counterpart and handoff discovery requires exact Jira, Hub, or contract
  evidence plus developer confirmation where the mapping is not unique.
- Cross-repository writes require `CROSS_REPO_POLICY=profile-controlled`.
- `explicit-only` narrows this pack and disables automatic counterpart use.
- The current central inventory has no exact counterpart/workflow mapping, so
  every current `cross-repo-write` returns `ROUTING_REQUIRED` before client
  inspection.
