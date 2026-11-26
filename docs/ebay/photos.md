# Photos

A draft holds up to 24 photos.

## Upload

The listing page holds an `epsData` object. The upload uses `endpoint` (on `mach-N.ebay.com`), `s`, `n`, `v`, `uaek`, `uaes`, `aXRequest`, and `wm`. It also holds `http2Endpoint`, `maxDimension`, `thumbnailDimension`, `quality`, `resolution`, `size`, `retry`, `type`, and `videoResolution`.

`POST {endpoint}&fileId=1&fId={epoch ms}&fileSize={bytes}&ar=/lstng`, as multipart. It sends the seven values other than `endpoint`, plus the image as `Filedata`, with the cookie. The page counts `fileId` up.

The response is `VERSION:2;<hosted url>`.

## Hosted URLs

`https://i.ebayimg.com/00/s/{dimensions}/z/{id}/$_1.{EXT}?set_id=…`

`{id}` names the photo. The page also serves it under other sizes, such as `$_57`.

## Put a photo on the draft

Save the hosted URL in `pictures`, on either route in [Saving](save.md).
