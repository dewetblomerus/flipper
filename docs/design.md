# Design notes

- Transitions live in one place so the allowed path stays obvious.
- The resize job is independent of other workers.
- Subject crop uses local background removal and a bounding box, not an LLM call.
- eBay API usage stays behind the approval gate.
- Start with the photo step only. Pricing research and other automations can be added later as new states and jobs.
