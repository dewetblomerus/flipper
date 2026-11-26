# Reading a draft

`GET https://www.ebay.com/lstng?draftId={id}&mode=SellLikeItem`, with the cookie and browser document headers.

The HTML embeds one JSON object per module, as `"TITLE":{"_type":"TitleViewHelix",…}`. A key repeats with `_type` `TextualDisplay` for labels.

A field is an object with a `name` and usually a `value`. For `title`, `subtitle`, `customLabel`, `itemConditionDescription`, and `universalProductCode`, `name` is also the key a save uses.

| Data | Location |
| --- | --- |
| Title, subtitle, custom label | `TITLE.titleField`, `.subtitleField`, `.customLabelField` |
| Condition description | `CONDITION`, field `itemConditionDescription` |
| Photos, main first | `PHOTOS.photosInput.photos[].url` |
| Item specifics | `ATTRIBUTES.attributeList[]` |
| UPC | `ATTRIBUTES`, field `universalProductCode` |

## Item specifics

- `name`: `attributes.<Label>`, such as `attributes.Color`
- `groups`: `REQUIRED`, `RECOMMENDED`, or `ADDITIONAL`
- `value`: a list of strings, such as `["Black"]`
- Other keys: `label.textSpans`, `format`, `maxLength`, `readOnly`, `options`, `customValuesAllowed`, `multiSelectEnabled`, `searchable`, `productSpecific`, `customSpecific`, `dependentAttributes`
