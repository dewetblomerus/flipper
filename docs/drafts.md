# Drafts

A person pastes an eBay draft URL. Flipper reads `draft_id` or `draftId` from the query string and creates one draft in `started`. The stored value is `drafts.ebay_draft_id`.

While no eBay cookie is saved, or after eBay redirects it to sign-in, a popover blocks every page and asks for one. Saving it enqueues a job for each failed read, photo replacement, and field removal.

An Oban job then reads that Seller Hub draft with the saved cookie. It stores the title and downloads every photo at eBay's largest size. Saved photos move the draft to `photos_taken`. A draft with no photos moves to `awaiting_photos`. Refresh on `/drafts/:id` reads the Seller Hub draft again when the draft has no photos.

`photos_taken` starts one edit job for the first photo. The job finds the subject and crops that original photo toward a square, keeping a margin around the subject. A photo that is not 3:4 or 4:3 keeps its whole frame. The job brightens the result by 50%. The background stays. It stores the edited file and the subject box. Later photos are not cropped. When the first photo has an edit, the draft moves to `photo_edits_drafted`. `/drafts/:id` shows the title, the first photo's original beside its edit, and the later photos unchanged. Until that job finishes, the edit side shows Editing. Redo edit clears the first photo's edit and runs the job again. The draft returns to `photos_taken` until it finishes.

The person picks one side of the first photo. That pick is `photos.use_edited` and approves it: the draft moves to `photo_edits_approved`, and the pick and the edit are locked. Picking the edit enqueues one Oban job. With the saved cookie, it uploads the edit to eBay and saves the Seller Hub draft with that photo first. `/drafts/:id` shows Replacing on eBay, Replaced on eBay, or the last error with Retry.

Sell similar fills fields that can be wrong. After the edit replaces the photo, or as soon as the original is picked, a job reads the Seller Hub draft and keeps every module as the draft's snapshot, with photos as URLs. The snapshot holds the approved photo and every field before removal. It is never overwritten, and a read without item specifics is not kept.

The draft moves to `field_removals_drafted`. `/drafts/:id` lists each filled optional field, ticked: item specifics eBay groups as Recommended or Additional, the subtitle, and the UPC. Required specifics, Brand, read-only specifics, and every other field are never listed.

The person unticks any field to keep and approves. The draft moves to `field_removals_approved`. A job removes the ticked fields in one save, reads the draft back, and moves it to `finished` once they are empty. A draft with no field to list moves straight to `finished`. `/drafts/:id` shows the last error with Retry.

See [eBay draft API](ebay/README.md).

`ebay_draft_id` identifies the Seller Hub draft. eBay assigns the published listing id when the listing is created: [ItemID](https://developer.ebay.com/Devzone/XML/docs/Reference/eBay/types/ItemType.html#ItemID) on the Trading API, and [listingId](https://developer.ebay.com/api-docs/sell/inventory/resources/offer/methods/publishOffer) when an Inventory API offer is published. A sell-similar URL carries this draft's id, not the source listing's item id.

Pasting an id that already exists opens that draft.

`/drafts` lists each draft with its first photo. `/drafts/new` pastes a URL. `/drafts/:id` opens one.

`/auto` shows one pending decision at a time as that draft's page, furthest along first, then oldest draft. A draft in `field_removals_drafted` has its removals pending, and one in `photo_edits_drafted` has a photo pick pending. The page keeps a decision while it is pending, then shows the next. With none pending, it says Nothing to decide until one arrives.

# To-do

## Published listing

A published eBay listing is a `listings` row with `ebay_listing_id`. It references the draft. `ebay_listing_id` is a separate name from `ebay_draft_id`.

## Ingest every draft

Every Seller Hub draft becomes a draft in `started`, using the same `ebay_draft_id` as a pasted URL. The paste flow comes first.
