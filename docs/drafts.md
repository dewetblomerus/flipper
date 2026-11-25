# Drafts

A person pastes an eBay draft URL. Flipper reads `draft_id` or `draftId` from the query string and creates one draft in `started`. The stored value is `drafts.ebay_draft_id`.

The drafts index asks for the eBay cookie and saves it. An Oban job then reads that Seller Hub draft with the saved cookie. It stores the title and downloads every photo. Saved photos move the draft to `photos_taken`. A draft with no photos moves to `awaiting_photos`. Refresh on `/drafts/:id` reads the Seller Hub draft again when the draft has no photos.

`photos_taken` starts one edit job per photo. The job removes the background, crops to the subject, and stores the edited file and the subject box. When every photo has an edit, the draft moves to `photo_edits_drafted`. `/drafts/:id` shows the title and each original on the left of its edit. The person picks one side per photo. That choice is `photos.use_edited`. A photo whose job has not finished shows Editing.

That value is the Seller Hub draft. eBay assigns the published listing id when the listing is created: [ItemID](https://developer.ebay.com/Devzone/XML/docs/Reference/eBay/types/ItemType.html#ItemID) on the Trading API, and [listingId](https://developer.ebay.com/api-docs/sell/inventory/resources/offer/methods/publishOffer) when an Inventory API offer is published. A sell-similar URL carries this draft's id, not the source listing's item id.

Pasting an id that already exists opens that draft.

`/drafts` lists each draft with its first photo. `/drafts/new` pastes a URL. `/drafts/:id` opens one.

# To-do

## Published listing

A published eBay listing is a `listings` row with `ebay_listing_id`. It references the draft. `ebay_listing_id` is a separate name from `ebay_draft_id`.

## Ingest every draft

Every Seller Hub draft becomes a draft in `started`, using the same `ebay_draft_id` as a pasted URL. The paste flow comes first.
