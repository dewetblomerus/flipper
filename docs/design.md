# Design notes

- Transitions live in one place so the allowed path stays obvious.
- The photo edit job is independent of other workers.
- Subject crop uses local Grounding DINO to find the subject, then crops the original. Only the first photo is cropped. The background stays.
- The subject is the best match for the draft title joined with every match for "product". A "product" match over 80% of the photo's area is the scene and is left out.
- Only a 3:4 or 4:3 photo is cropped. Any other shape is already cropped and keeps its whole frame.
- The crop never cuts the subject or adds pixels.
- The crop keeps a margin of 5% of the subject's longest side, as far as the photo reaches.
- The crop is as close to square as those two rules and the photo allow.
- The edit is 50% brighter than the original.
- Reading and writing a Seller Hub draft use the seller's session. No public eBay API edits a draft; Flipper uses the [private one](ebay/README.md). Every write to eBay stays behind an approval, and each approval is a draft state.
- Replacing the photo, reading the draft, and removing fields are separate jobs.
- Every Oban worker that calls eBay runs in `ebay`, for what a person starts, or `ebay_automated`, for unattended work. Each has a limit of 1 per node.
- `ebay_automated` has a jittered 10s dispatch cooldown, so its jobs start at least 5s apart.
- The automated steps are the drafts import and the photo edit. Further automations are new states and jobs.
- Single household, and strictly single tenant. One database is the whole business. A multi-tenant SaaS is a rewrite on a fresh database.

# To-do

## Permissions

A permission limits which human step a user can perform. An outsourced worker receives only that step.
