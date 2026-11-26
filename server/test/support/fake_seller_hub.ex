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

  def read_draft("502"), do: {:error, "eBay returned 502"}

  def read_draft(ebay_draft_id) do
    send(self(), {:ebay_draft_read, ebay_draft_id})
    {:ok, modules(ebay_draft_id)}
  end

  def remove_fields("501", _names), do: {:error, "eBay returned 501"}

  def remove_fields(ebay_draft_id, names) do
    send(self(), {:ebay_fields_removed, ebay_draft_id, names})
    :ok
  end

  # Draft "33" has no optional field filled.
  defp modules("33") do
    %{"ATTRIBUTES" => %{"attributeList" => []}, "TITLE" => %{}}
  end

  defp modules(_ebay_draft_id) do
    %{
      "ATTRIBUTES" => %{
        "attributeList" => [
          specific("Brand", "REQUIRED", "Acme"),
          specific("Color", "RECOMMENDED", "Black")
        ]
      },
      "TITLE" => %{"subtitleField" => %{"name" => "subtitle", "value" => "Works"}}
    }
  end

  defp specific(label, group, value) do
    %{"name" => "attributes." <> label, "groups" => [group], "value" => [value]}
  end
end
