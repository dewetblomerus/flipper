# Drafts

A person pastes an eBay draft URL. Flipper reads `draft_id` from the query string and creates one listing in `started`. The stored value is `listings.ebay_draft_id`.

That value is the Seller Hub draft. eBay assigns the published listing id when the listing is created: [ItemID](https://developer.ebay.com/Devzone/XML/docs/Reference/eBay/types/ItemType.html#ItemID) on the Trading API, and [listingId](https://developer.ebay.com/api-docs/sell/inventory/resources/offer/methods/publishOffer) when an Inventory API offer is published. A sell-similar URL carries this draft's id, not the source listing's item id.

Pasting an id that already exists opens that listing.

# To-do

## Ingest every draft

Every Seller Hub draft becomes a listing in `started`, using the same `ebay_draft_id` as a pasted URL. The paste flow comes first.
