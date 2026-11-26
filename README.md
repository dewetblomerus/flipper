# Flipper

A small Phoenix LiveView + PostgreSQL app that prepares eBay listings for a personal flipping workflow. It automates one step at a time. Earlier steps stay as they are.

## What it does

Drafts are imported from the Seller Hub drafts list, or created by pasting an eBay draft URL. A job then reads the title, Custom label (SKU), and photos from Seller Hub. Photo work waits for both a SKU and photos. Each draft moves through an explicit state machine. The automated transition crops the first photo toward a square around the subject and brightens it. Other steps are manual.

An approval step sits between the processed photo and any write to eBay. Nothing is uploaded until it has been reviewed. A second approval picks the optional fields to remove from the eBay draft.

### States

1. `started` — the draft exists
2. `awaiting_sku` — the Seller Hub draft was read without both photos and a SKU
3. `photos_taken` — raw photos are available
4. `photo_edits_drafted` — automatic edits are ready for review
5. `photo_edits_approved` — the photo pick is approved
6. `field_removals_drafted` — the optional fields are ready for review
7. `field_removals_approved` — the removals are approved
8. `finished` — the eBay draft is updated

The current state is a name. A transition adds a state name or returns to an earlier one. Drafts already past that point stay where they are.

## Docs

- [Stack](docs/stack.md)
- [Design notes](docs/design.md)
- [Drafts](docs/drafts.md)
- [eBay draft API](docs/ebay/README.md)
- [Entity relationship diagram](docs/erd.md)
