# Saving

Each save is a `PUT` of JSON with `?mode=SellLikeItem`.

| Route under `/lstng/api/listing_draft/{id}` | Saves | Success |
| --- | --- | --- |
| none | Title, item specifics, other fields, photos | 200, with changed modules (about 1 MB) |
| `/skip_validation` | Photos | 204 |
| `/preference_only` | `attributeViewSelection` | 200 |

`skip_validation` ignores `title` and `attributes` and still returns 204. From the page: it uses this route when a change holds only photo, video, and request keys.

One request to the main route can change everything at once:

```json
{
  "title": "New title",
  "pictures": ["<hosted url>", "<hosted url>"],
  "attributes": {"Type": [], "Color": []},
  "subtitle": "",
  "customLabel": "",
  "itemConditionDescription": "",
  "removedFields": ["universalProductCode"],
  "requestId": "<uuid>",
  "requestMeta": {"lastDeltaTimestamp": 1795600000000}
}
```

`lastDeltaTimestamp` is the current time in epoch milliseconds.

- A save is partial. Absent fields keep their values.
- `attributes` merges by label. Absent specifics keep their values.
- `pictures` is the whole list. A photo left out is removed.
- The main route's response holds the changed modules, `meta`, `_tracking`, `XS_rlogid`, and `requestMeta`. Unchanged modules can be absent.

## Values

| Key | Set | Empty |
| --- | --- | --- |
| `title` | String, 80 max | |
| `pictures` | Hosted URLs, main first | |
| `attributes` | `{"Color": ["Black"]}` | `{"Color": []}` |
| `subtitle` | String, 55 max | `""` |
| `customLabel` | String, 50 max | `""` |
| `itemConditionDescription` | String, 1000 max | `""` |
| `universalProductCode` | String, with `"includeEBayProduct": false` | Name it in `removedFields`. `""` leaves it set. |

The page also sends `"errorFieldFilters": ["universalProductCode"]` with a UPC.

A new label in `attributes` adds a custom item specific, marked `customSpecific` in the `ADDITIONAL` group. `[]` removes it.

From the page: `removedFields` also clears the description, reserve price, and Buy It Now price.

## Behavior

- A success status does not prove a field changed. Read the draft again to confirm.
- A required item specific can be saved empty.
- A rejected UPC returns 200 and stays unsaved.
- Saving a UPC can fill item specifics. One filled Country of Origin, and a later `""` for the UPC emptied that specific while the UPC stayed.
- Emptied specifics stay empty when the page loads again.
- Setting or emptying `customLabel` flips `customLabelPref` to match.
- Saving specifics can change `attributeViewSelection` from `summary` to `selectOwnDetails`.
