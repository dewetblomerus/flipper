defmodule FlipperWeb.DraftLiveTest do
  use FlipperWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flipper.Drafts

  @url "https://www.ebay.com/lstng?mode=SellLikeItem&draft_id=5345502780022"

  describe "Index" do
    test "lists drafts", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      {:ok, _index_live, html} = live(conn, ~p"/drafts")

      assert html =~ "Listing Drafts"
      assert html =~ draft.ebay_draft_id
    end

    test "pasting a draft URL opens the draft, and pasting it again opens the same draft", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/drafts")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "Paste a URL")
               |> render_click()
               |> follow_redirect(conn, ~p"/drafts/new")

      assert form_live
             |> form("#draft-form", draft: %{url: "https://example.com/lstng?draft_id=123"})
             |> render_change() =~ "is not an eBay draft URL"

      submit =
        form_live
        |> form("#draft-form", draft: %{url: @url})
        |> render_submit()

      assert {:error, {:live_redirect, %{to: path}}} = submit
      assert {:ok, show_live, html} = follow_redirect(submit, conn, path)
      assert html =~ "5345502780022"
      assert html =~ "started"

      assert {:ok, index_live, _html} =
               show_live
               |> element("a[href='/drafts']")
               |> render_click()
               |> follow_redirect(conn, ~p"/drafts")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "Paste a URL")
               |> render_click()
               |> follow_redirect(conn, ~p"/drafts/new")

      assert {:ok, _show_live, html} =
               form_live
               |> form("#draft-form", draft: %{url: @url})
               |> render_submit()
               |> follow_redirect(conn, path)

      assert html =~ "5345502780022"
    end
  end

  describe "Show" do
    test "displays draft", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      {:ok, _show_live, html} = live(conn, ~p"/drafts/#{draft}")

      assert html =~ "Draft #{draft.id}"
      assert html =~ draft.ebay_draft_id
      assert html =~ draft.state
    end
  end
end
