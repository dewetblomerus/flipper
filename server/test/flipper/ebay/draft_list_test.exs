defmodule Flipper.Ebay.DraftListTest do
  use ExUnit.Case, async: true

  alias Flipper.Ebay.SellerHub.DraftList

  @headers ~w(image title listingSKU createdDate)
  @photo ~s(<img loading=lazy src=//i.ebayimg.com/00/s/abc/$_1.JPG alt="Draft photo">)
  @placeholder ~s(<svg class="icon icon-pictures-null"></svg>)

  test "reads each row's title, SKU, and whether it has a photo" do
    rows = [
      row("111", "Lamp &amp; shade", "A-1", @photo),
      row("222", "", "", @placeholder)
    ]

    assert DraftList.parse(page(@headers, rows)) ==
             {:ok,
              [
                %{
                  ebay_draft_id: "111",
                  title: "Lamp & shade",
                  sku: "A-1",
                  photo?: true,
                  listed_at: nil
                },
                %{ebay_draft_id: "222", title: "", sku: "", photo?: false, listed_at: nil}
              ]}
  end

  test "reads the created date as Pacific time in the latest past year" do
    now = ~U[2026-11-26 04:00:00.000000Z]

    dates = [
      {"Nov 24 at 7:24pm PST", ~U[2026-11-25 03:24:00.000000Z]},
      {"Sep 3 at 12:05am PDT", ~U[2026-09-03 07:05:00.000000Z]},
      {"Nov 25 at 12:30pm PST", ~U[2026-11-25 20:30:00.000000Z]},
      {"Nov 25 at 8:00pm PST", ~U[2026-11-26 04:00:00.000000Z]},
      {"Nov 25 at 8:01pm PST", ~U[2025-11-26 04:01:00.000000Z]},
      {"Dec 20 at 9:00am PST", ~U[2025-12-20 17:00:00.000000Z]},
      {"yesterday", nil},
      {"", nil}
    ]

    for {text, expected} <- dates do
      rows = [row("111", "Lamp", "", @placeholder, text)]

      assert {:ok, [%{listed_at: ^expected}]} = DraftList.parse(page(@headers, rows), now)
    end
  end

  test "an empty list has no drafts" do
    assert DraftList.parse(page(@headers, [])) == {:ok, []}
  end

  test "a page without the list is an error" do
    assert {:error, _} = DraftList.parse("<html><body>Sign in</body></html>")
  end

  test "a list with a hidden column is an error" do
    for hidden <- ~w(image listingSKU) do
      assert {:error, _} = DraftList.parse(page(@headers -- [hidden], []))
    end
  end

  test "a row without its cells is an error" do
    rows = [~s(<tbody><tr data-id=111 class=grid-row><td>Lamp</td></tr></tbody>)]

    assert {:error, _} = DraftList.parse(page(@headers, rows))
  end

  defp page(headers, rows) do
    heading =
      Enum.map_join(headers, fn name ->
        ~s(<th class="shui-dt-column__#{name}" data-id=#{name}>#{name}</th>)
      end)

    ~s(<html><body><table role=grid><thead><tr class=header-row>#{heading}</tr></thead>) <>
      Enum.join(rows) <> "</table></body></html>"
  end

  # The page comments around each value, as its renderer does.
  defp row(id, title, sku, image, created \\ "") do
    ~s(<tbody><tr data-id=#{id} data-site=0 class=grid-row>) <>
      cell("image", image) <>
      cell("title", "<!--F#1-->#{title}<!--F/-->") <>
      cell("listingSKU", "<!--F#1-->#{sku}<!--F/-->") <>
      cell("createdDate", "<!--F#1-->#{created}<!--F/-->") <>
      "</tr></tbody>"
  end

  defp cell(name, content) do
    ~s(<td class="shui-dt-column__#{name} shui-dt--left"><div class=cell-wrapper>) <>
      ~s(<div>#{content}</div></div></td>)
  end
end
