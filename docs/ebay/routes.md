# Other routes and page behavior

## Routes

From the page's token map. All are under `/lstng`.

| Route | Name suggests |
| --- | --- |
| `api/listing_draft/{id}/get_attribute_details` | Item specific details |
| `api/listing_draft/{id}/publish` | Publishes the listing |
| `api/listing_draft/create_and_open` | New draft |
| `api/listing_draft/{id}/add_photo_from_mobile` | Phone upload |
| `api/listing_draft/tracking` | Analytics |
| `api/listing_draft/{id}/template`, `create_template`, `update_template` | Listing templates |
| `api/listing_draft/create_and_open_template`, `create_and_open_smp_product`, `create_and_open_smp_template` | New template or product |
| `api/listing_draft/{id}/smp_product`, `create_smp_product`, `smp_template`, `create_smp_template`, `update_smp_template`, `create_and_list_smp_template`, `update_and_list_smp_template` | Product and template variants |
| `api/create-description-template`, `update-description-template`, `delete-description-template` | Description templates |
| `api/image-background-remove` | Background removal |
| `api/upload-video`, `upload-video-id`, `video-ownership` | Video |
| `api/sms-extracted-aspect` | Suggested specifics |
| `api/switch-tool` | Listing tool switch |
| `gql`, `api/ext-gql`, `api/shipping-gql` | GraphQL |

## Page behavior

- Before saving specifics, the page `POST`s `get_attribute_details` with `removedFields`, the filled `attributes`, and any UPC.
- After a title change, it sends the `ext-gql` query `suggestListingData`. Suggested specifics are opt-in.
- After a photo upload, it `POST`s `listing_draft/tracking` and saves on `skip_validation`.
- It also sends `POST /gh/gadget_csm`.
- Its scripts load from `ir.ebaystatic.com/rs/c/fehelix/`. From the page: `list_*.js` holds the save logic, and save URLs can add `forceValidation` and `cgMandate`.
