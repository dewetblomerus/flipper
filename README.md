# Flipper

A small Phoenix LiveView + PostgreSQL app that prepares eBay listings for a personal flipping workflow. It automates one step at a time so the process can grow without rewriting earlier work.

## What it does

Each listing moves through an explicit state machine. The first automated transition resizes and crops photos tightly around the subject. Everything else stays manual until you choose to automate it.

An approval step sits between the processed photo and any call to the eBay API. Nothing is uploaded until it has been reviewed.

### Initial states

1. `start`
2. `photos_taken` — raw photos are available
3. `photos_resized` — background removed and cropped (automated)
4. `photos_approved` — manual review complete; later transitions may call eBay

New states can be inserted between existing ones later by adding a transition. Already-processed listings are unaffected.

## Docs

- [Stack](docs/stack.md)
- [Design notes](docs/design.md)
- [Entity relationship diagram](docs/erd.md)
