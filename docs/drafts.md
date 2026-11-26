# Drafts

A person pastes an eBay draft URL. Flipper reads `draft_id` or `draftId` from the query string and creates one draft in `started`. The stored value is `drafts.ebay_draft_id`.

While no eBay cookie is saved, or after eBay rejects it, a popover blocks every page and asks for one. A page read answered with a sign-in redirect, a browser check, 403, or 429 rejects it. Saving a cookie enqueues a job for each failed read, photo replacement, and field removal. Those reads run in the paced queue. The popover keeps its field focused for pasting.

The cookie is saved to `~/code/flipper/ebay_cookie`, or `/code/flipper/ebay_cookie` without a home directory. A rejection is saved beside it in `ebay_cookie.rejected`. Every worktree's server uses both files and notices a change within a second.

Flipper also reads the Seller Hub drafts list hourly, as each server starts, and on Refresh Drafts: one request for up to 200 drafts. The start read also checks the cookie. A server whose cookie is missing or rejected reads nothing. The list needs its photo and Custom label (SKU) columns.

Each unknown draft is added. One listed with both a SKU and a photo is read in the paced queue. Any other waits unread in `awaiting_sku` with the listed title and SKU, and is read once the list shows both. An import queues a draft's read at most once a day, and leaves a failed read to Refresh or a saved cookie. An import never writes to eBay.

Pasting or refreshing a draft whose read waits in the paced queue moves it to the `ebay` queue.

An Oban job reads the Seller Hub draft with the saved cookie. It stores the title and the Custom label (SKU). A draft with both a SKU and photos downloads every photo at eBay's largest size and moves to `photos_taken`. Any other draft moves to `awaiting_sku` with no photos saved. Refresh on `/drafts/:id` reads the Seller Hub draft again when the draft has no photos.

`photos_taken` starts one edit job for the first photo. The job finds the subject and crops that original photo toward a square, keeping a margin around the subject. A photo that is not 3:4 or 4:3 keeps its whole frame. The job brightens the result by 50%. The background stays. It stores the edited file and the subject box. Later photos are not cropped. When the first photo has an edit, the draft moves to `photo_edits_drafted`. `/drafts/:id` shows the title, the first photo's original beside its edit, and the later photos unchanged. Until that job finishes, the edit side shows Editing. Redo edit clears the first photo's edit and runs the job again. The draft returns to `photos_taken` until it finishes.

The person picks one side of the first photo. That pick is `photos.use_edited` and approves it: the draft moves to `photo_edits_approved`, and the pick and the edit are locked. Picking the edit enqueues one Oban job. With the saved cookie, it uploads the edit to eBay and saves the Seller Hub draft with that photo first. `/drafts/:id` shows Replacing on eBay, Replaced on eBay, or the last error with Retry.

<!-- coderabbit-ai-generated:v1 -->

<!-- coderabbit-ai-generated-section:v1:6192e19deb76cd461b59bdbeb300001109af63ca936ee7f1d5942989b872b463 -->

Sell similar fills fields that can be wrong. After the edit replaces the photo, or as soon as the original is picked, a job reads the Seller Hub draft and keeps every module as the draft's snapshot, with photos as URLs. The snapshot holds the approved photo and every field before removal. A read must include item specifics and the title module. A valid snapshot is kept unchanged; a valid read replaces an invalid stored snapshot.

<!-- /coderabbit-ai-generated:v1 -->

The draft moves to `field_removals_drafted`. `/drafts/:id` lists each filled optional field, ticked: item specifics eBay groups as Recommended or Additional, the subtitle, and the UPC. Required specifics, Brand, read-only specifics, and every other field are never listed.

The person unticks any field to keep and approves. The draft moves to `field_removals_approved`. A job removes the ticked fields in one save, reads the draft back, and moves it to `finished` once they are empty. A draft with no field to list moves straight to `finished`. `/drafts/:id` shows the last error with Retry.

See [eBay draft API](ebay/README.md).

`ebay_draft_id` identifies the Seller Hub draft. eBay assigns the published listing id when the listing is created: [ItemID](https://developer.ebay.com/Devzone/XML/docs/Reference/eBay/types/ItemType.html#ItemID) on the Trading API, and [listingId](https://developer.ebay.com/api-docs/sell/inventory/resources/offer/methods/publishOffer) when an Inventory API offer is published. A sell-similar URL carries this draft's id, not the source listing's item id.

Pasting an id that already exists opens that draft.

`/drafts` lists each draft with its first photo and updates as drafts change. Refresh Drafts queues an import in the `ebay` queue, taking over one waiting in the paced queue. One import job waits or runs at a time. The page shows Refreshing, then the result. `/drafts/new` pastes a URL. `/drafts/:id` opens one.

`/auto` shows one pending decision at a time as that draft's page, furthest along first, then oldest draft. A draft in `field_removals_drafted` has its removals pending, and one in `photo_edits_drafted` has a photo pick pending. The page keeps a decision while it is pending, then shows the next. With none pending, it says Nothing to decide until one arrives.

# To-do

## Published listing

A published eBay listing is a `listings` row with `ebay_listing_id`. It references the draft. `ebay_listing_id` is a separate name from `ebay_draft_id`.
