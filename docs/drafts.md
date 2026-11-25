# Drafts

A person pastes an eBay draft URL. Flipper reads `draft_id` or `draftId` from the query string and creates one draft in `started`. The stored value is `drafts.ebay_draft_id`.

While no eBay cookie is saved, or after eBay redirects it to sign-in, a popover blocks every page and asks for one. Saving it enqueues a job for each failed read and photo replacement.

An Oban job then reads that Seller Hub draft with the saved cookie. It stores the title and downloads every photo. Saved photos move the draft to `photos_taken`. A draft with no photos moves to `awaiting_photos`. Refresh on `/drafts/:id` reads the Seller Hub draft again when the draft has no photos.

`photos_taken` starts one edit job for the first photo. The job finds the subject, turns the photo to square its straight edges, and crops it with a margin. The background stays. It stores the edited file, the subject box, and the angle. Later photos are not cropped. When the first photo has an edit, the draft moves to `photo_edits_drafted`. `/drafts/:id` shows the title, the first photo's original beside its edit, and the later photos unchanged. Until that job finishes, the edit side shows Editing. Redo edit clears the first photo's edit and runs the job again. The draft returns to `photos_taken` until it finishes.

The person picks one side of the first photo. That pick is `photos.use_edited` and approves it: the draft moves to `photo_edits_approved`, and the pick and the edit are locked. Picking the original makes no eBay call. Picking the edit enqueues one Oban job. With the saved cookie, it uploads the edit to eBay and saves the Seller Hub draft with that photo first. `/drafts/:id` shows Replacing on eBay, Replaced on eBay, or the last error with Retry.

That value is the Seller Hub draft. eBay assigns the published listing id when the listing is created: [ItemID](https://developer.ebay.com/Devzone/XML/docs/Reference/eBay/types/ItemType.html#ItemID) on the Trading API, and [listingId](https://developer.ebay.com/api-docs/sell/inventory/resources/offer/methods/publishOffer) when an Inventory API offer is published. A sell-similar URL carries this draft's id, not the source listing's item id.

Pasting an id that already exists opens that draft.

`/drafts` lists each draft with its first photo. `/drafts/new` pastes a URL. `/drafts/:id` opens one.

# To-do

## Published listing

A published eBay listing is a `listings` row with `ebay_listing_id`. It references the draft. `ebay_listing_id` is a separate name from `ebay_draft_id`.

## Ingest every draft

Every Seller Hub draft becomes a draft in `started`, using the same `ebay_draft_id` as a pasted URL. The paste flow comes first.
