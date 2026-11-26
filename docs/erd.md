# Entity relationship diagram

Auth follows [Done Manager](https://github.com/dewetblomerus/donemanager): Ueberauth Auth0. A sign-in upserts `users` on `auth0_sub` and refreshes `email` and `display_name`.

One database is the household. Drafts are shared by everyone who can sign in. A multi-tenant SaaS is a rewrite on a fresh database.

```mermaid
erDiagram
    drafts ||--o{ photos : has
    drafts ||--o| draft_snapshots : keeps

    users {
        bigint id PK
        string auth0_sub UK "not null"
        string email UK "not null"
        string display_name
        datetime inserted_at
        datetime updated_at
    }

    drafts {
        bigint id PK
        string ebay_draft_id UK "not null"
        string title
        string state "not null"
        string fetch_error
        string[] approved_removals
        string removal_error
        datetime inserted_at
        datetime updated_at
    }

    photos {
        bigint id PK
        bigint draft_id FK "not null"
        integer position "not null"
        string original_path "not null"
        string original_content_type "not null"
        string edited_path
        string edited_content_type
        integer subject_left
        integer subject_top
        integer subject_width
        integer subject_height
        boolean use_edited
        string edited_ebay_url
        datetime replaced_on_ebay_at
        string ebay_error
        datetime inserted_at
        datetime updated_at
    }

    draft_snapshots {
        bigint id PK
        bigint draft_id FK,UK "not null"
        jsonb modules "not null"
        datetime inserted_at
    }
```

## Notes

- Primary keys are `bigint`. Timestamps are UTC instants (`utc_datetime_usec`).
- `drafts.state` is the current state name: `started`, `awaiting_photos`, `photos_taken`, `photo_edits_drafted`, `photo_edits_approved`, `field_removals_drafted`, `field_removals_approved`, `finished`. Allowed moves live in code. A transition adds a state name or returns to an earlier one. Drafts already past that point stay where they are.
- A draft in `started` has not been read from eBay yet. `awaiting_photos` means it was read and it has no photos. `title` may be empty.
- `drafts.fetch_error` is the last failed read of the Seller Hub draft. A successful read clears it.
- `drafts.approved_removals` holds the eBay field names a person approved for removal. `removal_error` is the last failed read or removal after photo approval. Retry clears it.
<!-- coderabbit-ai-generated:v1 -->

<!-- coderabbit-ai-generated-section:v1:d1a6a225f7bcb4ddf3591ed4e82cda4571abc31ec90b9d3b17e34155508e140e -->

- `draft_snapshots.modules` is the first valid Seller Hub draft read after photo approval, keyed by eBay module name, without upload tokens. A draft has at most one. Deleting a draft deletes it.

<!-- /coderabbit-ai-generated:v1 -->
- `drafts.ebay_draft_id` is the Seller Hub `draft_id` from a pasted eBay draft URL. It is unique. See [Drafts](drafts.md).
- `photos.position` is unique per draft. Deleting a draft deletes its photos.
- `original_path` and `edited_path` are disk paths. The original is never replaced. The edit job crops that original to the subject box, brightens it, and writes `edited_path` and `edited_content_type`. The background stays. A rework overwrites the edit in place.
- The subject box is `subject_left`, `subject_top`, `subject_width`, and `subject_height`, in pixels of the original. It is the crop: the subject, its margin, and the surroundings that bring it toward a square. An already cropped photo stores its whole frame. Width and height count pixels. All four are null, or all four are present with width and height greater than zero. A check constraint enforces that. The crop reuses this box.
- `photos.use_edited` is true when the person picks the edit and false when they pick the original. It stays null until they choose. The pick approves the draft.
- `edited_ebay_url` is the eBay-hosted copy of the approved edit. `replaced_on_ebay_at` is when the Seller Hub draft saved it as the first photo. `ebay_error` is the last failed replacement. Retry clears it.
- An approved draft sends `edited_path` to eBay only when `use_edited` is true.
- Reaching `photos_taken` enqueues one Oban edit job for the first photo. Later photos are not cropped. The draft moves to `photo_edits_drafted` when that photo has an edit.
