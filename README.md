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

## Stack

- Elixir / Phoenix LiveView
- PostgreSQL
- Oban (open-source) for background jobs
- [rembg](https://github.com/danielgatis/rembg) (local CPU) plus a normal image library for the crop and resize
- Fly.io — a small shared-cpu machine is sufficient

## Design notes

- Transitions live in one place so the allowed path stays obvious.
- The resize job is independent of other workers.
- Subject crop uses local background removal and a bounding box, not an LLM call.
- eBay API usage stays behind the approval gate.
- Start with the photo step only. Pricing research and other automations can be added later as new states and jobs.
