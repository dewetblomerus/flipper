# Design notes

- Transitions live in one place so the allowed path stays obvious.
- The resize job is independent of other workers.
- Subject crop uses local background removal and a bounding box, not an LLM call.
- eBay API usage stays behind the approval gate. Approval is one listing state, not a state per photo.
- Start with the photo step only. Pricing research and other automations can be added later as new states and jobs.
- Single household, and strictly single tenant. One database is the whole business. Users may later get permissions so a human step can be handed to an outsourced worker. That is not a tenant split. A multi-tenant SaaS would be a rewrite on a fresh database.
