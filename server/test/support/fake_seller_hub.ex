defmodule Flipper.Ebay.FakeSellerHub do
  @jpeg <<0xFF, 0xD8, 0xFF, 0xD9>>

  def fetch("0") do
    {:ok, %{title: "Bare item", photo_urls: []}}
  end

  def fetch("404") do
    {:error, "eBay did not return the draft"}
  end

  def fetch(_ebay_draft_id) do
    {:ok,
     %{
       title: "Vintage lamp",
       photo_urls: ["https://i.ebayimg.com/images/g/abc/s-l1600.jpg"]
     }}
  end

  def download(_url), do: {:ok, @jpeg, "image/jpeg"}
end
