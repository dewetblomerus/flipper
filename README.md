# Flipper

A small Phoenix LiveView + PostgreSQL app that prepares eBay listings for a personal flipping workflow. It automates one step at a time. Earlier steps stay as they are.

## What it does

A person pastes an eBay draft URL to create a draft. A job then reads the title and photos from Seller Hub. Each draft moves through an explicit state machine. The automated transition resizes and crops photos tightly around the subject. Other steps are manual.

An approval step sits between the processed photo and any call to the eBay API. Nothing is uploaded until it has been reviewed.

### States

1. `started` — the draft exists
2. `awaiting_photos` — the Seller Hub draft was read and it has no photos
3. `photos_taken` — raw photos are available
4. `photo_edits_drafted` — automatic edits are ready for review
5. `photo_edits_approved` — review is complete

The current state is a name. A transition adds a state name or returns to an earlier one. Drafts already past that point stay where they are.

## Docs

- [Stack](docs/stack.md)
- [Design notes](docs/design.md)
- [Drafts](docs/drafts.md)
- [Entity relationship diagram](docs/erd.md)
