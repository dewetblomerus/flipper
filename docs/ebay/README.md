# eBay draft API

Seller Hub's listing page reads and saves drafts through private endpoints. eBay publishes no documentation for them and can change them at any time.

Facts here come from live eBay on 2026-11-25. "From the page" marks what the page's HTML or JavaScript shows without a test save. "From the client" marks what Flipper's [client](../../server/lib/flipper/ebay/seller_hub/client.ex) handles.

- [Reading a draft](read.md)
- [Fields](fields.md)
- [Saving](save.md)
- [Photos](photos.md)
- [Other routes and page behavior](routes.md)

## Access

- The seller's browser cookie authenticates every request.
- A signed-out cookie redirects to sign-in.
- From the client: a `/splashui/challenge` redirect or "Pardon Our Interruption" is a browser check.
- The drafts list is `https://www.ebay.com/sh/lst/drafts`.
- The client reads the page, uploads photos, and saves photos and fields from the server.

## Tokens

The listing page maps each write route to a token, in HTML-escaped JSON:

```text
"/lstng/api/listing_draft/:draftId(\\d+)":"<token>"
"/lstng/api/listing_draft/:draftId(\\d+)/skip_validation":"<token>"
```

A write sends its route's token in the `srt` header.
