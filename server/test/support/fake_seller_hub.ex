defmodule Flipper.Ebay.FakeSellerHub do
  @moduledoc """
  Seller Hub stand-in for tests.
  """

  @jpeg <<0xFF, 0xD8, 0xFF, 0xD9>>

  # A test sets the drafts list, or one draft's read, in its process.
  def drafts do
    send(self(), :ebay_drafts_listed)
    Process.get(:ebay_drafts, {:ok, []})
  end

  def fetch(ebay_draft_id) do
    with {:ok, read} <- Process.get({:ebay_draft, ebay_draft_id}) || read(ebay_draft_id) do
      {:ok, Map.put_new(read, :modules, modules(ebay_draft_id))}
    end
  end

  defp read("0") do
    {:ok, %{title: "Bare item", sku: "BARE-1", photo_urls: []}}
  end

  defp read("11") do
    {:ok,
     %{
       title: "Unlabelled lamp",
       sku: nil,
       photo_urls: ["https://i.ebayimg.com/images/g/abc/s-l1600.jpg"]
     }}
  end

  defp read("404") do
    {:error, "eBay did not return the draft"}
  end

  defp read("22") do
    {:ok,
     %{
       title: "Pair of lamps",
       sku: "PAIR-1",
       photo_urls: [
         "https://i.ebayimg.com/images/g/abc/s-l1600.jpg",
         "https://i.ebayimg.com/images/g/def/s-l1600.jpg"
       ]
     }}
  end

  defp read(_ebay_draft_id) do
    {:ok,
     %{
       title: "Vintage lamp",
       sku: "LAMP-1",
       photo_urls: ["https://i.ebayimg.com/images/g/abc/s-l1600.jpg"]
     }}
  end

  def download(_url), do: {:ok, @jpeg, "image/jpeg"}

  def upload_photo(ebay_draft_id, path, content_type) do
    send(self(), {:ebay_photo_uploaded, ebay_draft_id, path, content_type})
    {:ok, "https://i.ebayimg.com/images/g/new/s-l1600.png"}
  end

  def update_draft("500", _changes), do: {:error, "eBay returned 500"}

  def update_draft(ebay_draft_id, changes) do
    send(self(), {:ebay_draft_updated, ebay_draft_id, changes})
    :ok
  end

  # Draft "503" is read without its item specifics.
  defp modules("503"), do: %{"ATTRIBUTES" => %{}, "TITLE" => %{}}

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
