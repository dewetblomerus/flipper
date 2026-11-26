# Listing drafts

`GET https://www.ebay.com/sh/lst/drafts?limit=200`, with the cookie and browser document headers.

The HTML holds one table. Each draft is a `tr.grid-row` whose `data-id` is the draft id. Each column has a header `th[data-id={column}]` and cells `td.shui-dt-column__{column}`.

| Data | Column |
| --- | --- |
| Title, which may be empty | `title` |
| Custom label (SKU), empty when unset | `listingSKU` |
| Created, as `Nov 24 at 7:24pm PST`, with no year | `createdDate` |
| Photo: an `img` on `ebayimg.com`, or a placeholder icon | `image` |

- The page's data includes `totalRecords`, `limit`, and `offset`.
- From the page: Customize table changes the columns.
