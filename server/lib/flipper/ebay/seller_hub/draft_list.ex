defmodule Flipper.Ebay.SellerHub.DraftList do
  @moduledoc """
  Reads the table on the Seller Hub drafts page. It needs the photo and Custom label
  columns, which a seller can hide.
  """

  @error {:error, "eBay drafts page had no list with photos and custom labels"}
  @headers ["th[data-id=image]", "th[data-id=listingSKU]"]
  @image ".shui-dt-column__image"
  @sku ".shui-dt-column__listingSKU"
  @title ".shui-dt-column__title"

  @doc """
  Returns each row as `%{ebay_draft_id: id, title: title, sku: sku, photo?: boolean}`.
  A blank title or SKU is "".
  """
  def parse(body) when is_binary(body) do
    page = LazyHTML.from_document(body)

    if Enum.all?(@headers, &present?(page, &1)) do
      page
      |> LazyHTML.query("tr.grid-row[data-id]")
      |> drafts()
    else
      @error
    end
  end

  defp drafts(rows) do
    if Enum.all?(rows, &complete?/1),
      do: {:ok, Enum.map(rows, &draft/1)},
      else: @error
  end

  defp complete?(row) do
    [id] = LazyHTML.attribute(row, "data-id")

    id =~ ~r/\A\d+\z/ and Enum.all?([@image, @sku, @title], &present?(row, "td" <> &1))
  end

  defp draft(row) do
    [id] = LazyHTML.attribute(row, "data-id")

    %{
      ebay_draft_id: id,
      title: cell(row, @title),
      sku: cell(row, @sku),
      photo?: present?(row, "td#{@image} img[src*='ebayimg.com']")
    }
  end

  defp cell(row, column) do
    row
    |> LazyHTML.query("td" <> column)
    |> LazyHTML.text()
    |> String.trim()
  end

  defp present?(html, selector), do: not Enum.empty?(LazyHTML.query(html, selector))
end
