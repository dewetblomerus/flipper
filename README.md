# Flipper

A small Phoenix LiveView + PostgreSQL app that prepares eBay listings for a personal flipping workflow. It automates one step at a time so the process can grow without rewriting earlier work.

## What it does

Each listing moves through an explicit state machine. The first automated transition resizes and crops photos tightly around the subject. Everything else stays manual until you choose to automate it.

An approval step sits between the processed photo and any call to the eBay API. Nothing is uploaded until it has been reviewed.

### Initial states

1. `start`
2. `photos_taken` — raw photos are available
3. `photo_edits_drafted` — automatic edits are ready for review
4. `photo_edits_approved` — review complete; later transitions may call eBay

The current state is a name, not a progress number. A later transition can add a name or return to an earlier one, such as `photo_edits_denied` back to `photo_edits_drafted`. Listings already further along stay where they are.

## Docs

- [Stack](docs/stack.md)
- [Design notes](docs/design.md)
- [Entity relationship diagram](docs/erd.md)
