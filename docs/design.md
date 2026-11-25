# Design notes

- Transitions live in one place so the allowed path stays obvious.
- The resize job is independent of other workers.
- Subject crop uses local background removal and a bounding box.
- Reading a Seller Hub draft uses the seller's session. Writing to eBay stays behind the approval gate. Approval is one draft state.
- The automated step is the photo edit. Further automations are new states and jobs.
- Single household, and strictly single tenant. One database is the whole business. A multi-tenant SaaS is a rewrite on a fresh database.

# To-do

## Permissions

A permission limits which human step a user can perform. An outsourced worker receives only that step.
