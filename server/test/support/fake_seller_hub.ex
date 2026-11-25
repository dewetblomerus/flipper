defmodule Flipper.Ebay.FakeSellerHub do
  @moduledoc """
  Seller Hub stand-in for tests.
  """

  @jpeg <<0xFF, 0xD8, 0xFF, 0xD9>>

  def fetch("0") do
    {:ok, %{title: "Bare item", photo_urls: []}}
  end

  def fetch("404") do
    {:error, "eBay did not return the draft"}
  end

  def fetch("22") do
    {:ok,
     %{
       title: "Pair of lamps",
       photo_urls: [
         "https://i.ebayimg.com/images/g/abc/s-l1600.jpg",
         "https://i.ebayimg.com/images/g/def/s-l1600.jpg"
       ]
     }}
  end

  def fetch(_ebay_draft_id) do
    {:ok,
     %{
       title: "Vintage lamp",
       photo_urls: ["https://i.ebayimg.com/images/g/abc/s-l1600.jpg"]
     }}
  end

  def download(_url), do: {:ok, @jpeg, "image/jpeg"}

  def upload_photo(ebay_draft_id, path, content_type) do
    send(self(), {:ebay_photo_uploaded, ebay_draft_id, path, content_type})
    {:ok, "https://i.ebayimg.com/images/g/new/s-l1600.png"}
  end

  def set_first_photo("500", _url), do: {:error, "eBay returned 500"}

  def set_first_photo(ebay_draft_id, url) do
    send(self(), {:ebay_first_photo_set, ebay_draft_id, url})
    :ok
  end
end
