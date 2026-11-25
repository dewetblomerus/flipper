defmodule FlipperWeb.DraftLiveTest do
  use FlipperWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flipper.Drafts

  @url "https://www.ebay.com/lstng?mode=SellLikeItem&draft_id=5345502780022"

  test "lists drafts and opens one", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/drafts")
    assert html =~ "No drafts yet."

    {:ok, draft} = Drafts.paste_url(@url)

    {:ok, view, html} = live(conn, ~p"/drafts")
    assert html =~ draft.ebay_draft_id
    refute html =~ "No drafts yet."

    assert {:ok, _show, html} =
             view
             |> element("#draft-#{draft.id}")
             |> render_click()
             |> follow_redirect(conn, ~p"/drafts/#{draft}")

    assert html =~ ~s(id="draft-id">#{draft.id}<)
  end

  test "pasting a draft URL opens the draft, and pasting it again opens the same draft", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:ok, _show, html} =
             view
             |> form("#draft-form", draft: %{url: @url})
             |> render_submit()
             |> follow_redirect(conn)

    assert html =~ "5345502780022"
    assert html =~ "started"
    [_, id] = Regex.run(~r/id="draft-id">(\d+)/, html)

    {:ok, view, _html} = live(conn, ~p"/")

    assert {:ok, _show, html} =
             view
             |> form("#draft-form", draft: %{url: @url})
             |> render_submit()
             |> follow_redirect(conn, ~p"/drafts/#{id}")

    assert html =~ ~s(id="draft-id">#{id}<)
  end
end
