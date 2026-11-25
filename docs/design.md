# Design notes

- Transitions live in one place so the allowed path stays obvious.
- The photo edit job is independent of other workers.
- Subject crop uses local Grounding DINO to find the product box from the draft title, then crops the original. Only the first photo is cropped. The background stays.
- Before the crop, the photo turns to square the product's straight edges. It stays put when those edges disagree, the tilt is under 1° or over 20°, or more than 1% of the crop would fall outside the original.
- The crop keeps a margin of 5% of the subject's average side. On a turned photo the margin narrows until no more than 1% of the crop falls outside the original.
- Reading and writing a Seller Hub draft use the seller's session. No public eBay API edits a draft. Writing to eBay stays behind the approval gate. Approval is one draft state.
- Every Oban worker that calls eBay runs in the `ebay` queue. Its limit of 1 per node keeps one eBay request in flight.
- The automated step is the photo edit. Further automations are new states and jobs.
- Single household, and strictly single tenant. One database is the whole business. A multi-tenant SaaS is a rewrite on a fresh database.

# To-do

## Permissions

A permission limits which human step a user can perform. An outsourced worker receives only that step.
