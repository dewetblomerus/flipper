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
  @created ".shui-dt-column__createdDate"

  @date ~r/\A([A-Z][a-z]{2}) (\d{1,2}) at (\d{1,2}):(\d{2})(am|pm) (P[SD]T)\z/
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  # Hours behind UTC.
  @offsets %{"PST" => 8, "PDT" => 7}

  @doc """
  Returns each row as `%{ebay_draft_id: id, title: title, sku: sku, photo?: boolean,
  listed_at: created}`. A blank title or SKU is "". `listed_at` is nil when the list has no
  readable created date.
  """
  def parse(body, now \\ DateTime.utc_now()) when is_binary(body) do
    page = LazyHTML.from_document(body)

    if Enum.all?(@headers, &present?(page, &1)) do
      page
      |> LazyHTML.query("tr.grid-row[data-id]")
      |> drafts(now)
    else
      @error
    end
  end

  defp drafts(rows, now) do
    if Enum.all?(rows, &complete?/1),
      do: {:ok, Enum.map(rows, &draft(&1, now))},
      else: @error
  end

  defp complete?(row) do
    [id] = LazyHTML.attribute(row, "data-id")

    id =~ ~r/\A\d+\z/ and Enum.all?([@image, @sku, @title], &present?(row, "td" <> &1))
  end

  defp draft(row, now) do
    [id] = LazyHTML.attribute(row, "data-id")

    %{
      ebay_draft_id: id,
      title: cell(row, @title),
      sku: cell(row, @sku),
      photo?: present?(row, "td#{@image} img[src*='ebayimg.com']"),
      listed_at: listed_at(cell(row, @created), now)
    }
  end

  # The list shows Pacific time without a year, as in "Nov 24 at 7:24pm PST". A draft is
  # never from the future, so a later date is last year's.
  defp listed_at(text, now) do
    with [_, month, day, hour, minute, half, zone] <- Regex.run(@date, text),
         index when is_integer(index) <- Enum.find_index(@months, &(&1 == month)) do
      hour = rem(String.to_integer(hour), 12) + if(half == "pm", do: 12, else: 0)
      time = {index + 1, String.to_integer(day), hour, String.to_integer(minute)}
      this_year = utc(now.year, time, @offsets[zone])

      if this_year && DateTime.diff(this_year, now, :hour) < 24,
        do: this_year,
        else: utc(now.year - 1, time, @offsets[zone])
    else
      _ -> nil
    end
  end

  defp utc(year, {month, day, hour, minute}, offset) do
    case NaiveDateTime.new(year, month, day, hour, minute, 0, {0, 6}) do
      {:ok, local} -> local |> DateTime.from_naive!("Etc/UTC") |> DateTime.add(offset, :hour)
      {:error, _reason} -> nil
    end
  end

  defp cell(row, column) do
    row
    |> LazyHTML.query("td" <> column)
    |> LazyHTML.text()
    |> String.trim()
  end

  defp present?(html, selector), do: not Enum.empty?(LazyHTML.query(html, selector))
end
