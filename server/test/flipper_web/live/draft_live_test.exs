defmodule FlipperWeb.DraftLiveTest do
  use FlipperWeb.ConnCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Flipper.Drafts
  alias Flipper.Drafts.Photo
  alias Flipper.Repo
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft
  alias Flipper.Workers.ReplaceEbayPhoto

  @url "https://www.ebay.com/lstng?mode=SellLikeItem&draft_id=5345502780022"

  describe "Index" do
    test "lists drafts", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      {:ok, _index_live, html} = live(conn, ~p"/drafts")

      assert html =~ "Listing Drafts"
      assert html =~ draft.ebay_draft_id
      assert html =~ "max-w-4xl"
      refute html =~ "/photos/"
    end

    test "shows the first photo before the draft id", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      later = insert_photo(draft, 2)
      first = insert_photo(draft, 1)

      {:ok, _index_live, html} = live(conn, ~p"/")

      assert html =~ ~s(src="#{~p"/photos/#{first}"}")
      refute html =~ ~s(src="#{~p"/photos/#{later}"}")
      assert html =~ ~r/src="#{Regex.escape(~p"/photos/#{first}")}"[\s\S]*#{draft.ebay_draft_id}/
    end

    test "pasting a draft URL opens the draft, and pasting it again opens the same draft", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/drafts")

      assert {:ok, form_live, form_html} =
               index_live
               |> element("a", "Paste a URL")
               |> render_click()
               |> follow_redirect(conn, ~p"/drafts/new")

      assert form_html =~ "max-w-2xl"
      refute form_html =~ "max-w-4xl"

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
      assert html =~ "started"
      assert html =~ "max-w-5xl"
      refute html =~ "max-w-2xl"
      refute html =~ "max-w-4xl"
      assert html =~ "Fetching title and photos."
      assert html =~ "Refresh"
    end

    test "refresh clears the fetch error and tries again", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=404")
      assert {:error, _} = perform_job(FetchDraft, %{draft_id: draft.id}, attempt: 3)

      Repo.update_all(
        from(j in Oban.Job, where: j.state == "available"),
        set: [state: "discarded"]
      )

      {:ok, view, html} = live(conn, ~p"/drafts/#{draft}")
      assert html =~ "eBay did not return the draft"

      html = view |> element("#refresh-draft", "Refresh") |> render_click()
      assert html =~ "Fetching title and photos."
      refute html =~ "eBay did not return the draft"
      assert [_] = all_enqueued(worker: FetchDraft, args: %{draft_id: draft.id})
    end

    test "serves a stored photo", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

      photo = hd(Drafts.get_draft!(draft.id).photos)
      conn = get(conn, ~p"/photos/#{photo}")

      assert conn.status == 200
      assert ["image/jpeg" <> _] = get_resp_header(conn, "content-type")
    end

    test "later photos stay original while the first photo is edited", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=22")
      {:ok, view, _html} = live(conn, ~p"/drafts/#{draft}")
      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

      [first, second] = Drafts.get_draft!(draft.id).photos
      assert has_element?(view, "#photo-#{first.id}-edited", "Editing")
      refute has_element?(view, "#photo-#{second.id}-edited")

      assert :ok = perform_job(EditPhoto, %{photo_id: first.id})
      html = render(view)
      assert html =~ "photo_edits_drafted"
      assert html =~ "/photos/#{first.id}/edited"
      refute has_element?(view, "#photo-#{second.id}-edited")
      assert has_element?(view, "#photo-#{second.id} img")
    end

    test "shows the title and photos when the fetch finishes", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      {:ok, view, _html} = live(conn, ~p"/drafts/#{draft}")

      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

      html = render(view)
      assert html =~ "Vintage lamp"
      assert html =~ "photos_taken"
      assert html =~ "/photos/"
      assert html =~ "Editing"
      refute html =~ "Refresh"
    end

    test "shows the original and the edit, and redo runs the edit again", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      {:ok, view, _html} = live(conn, ~p"/drafts/#{draft}")
      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

      photo = hd(Drafts.get_draft!(draft.id).photos)
      assert has_element?(view, "#photo-#{photo.id}-edited", "Editing")

      assert :ok = perform_job(EditPhoto, %{photo_id: photo.id})
      html = render(view)
      assert html =~ "photo_edits_drafted"
      assert html =~ "/photos/#{photo.id}/edited"
      refute html =~ "Editing"

      Repo.update_all(from(j in Oban.Job, where: j.state == "available"),
        set: [state: "discarded"]
      )

      html = view |> element("#redo-edits", "Redo edit") |> render_click()
      assert html =~ "Editing"
      assert html =~ "photos_taken"
      assert [_] = all_enqueued(worker: EditPhoto, args: %{photo_id: photo.id})
    end

    test "picking the edit approves it and replaces it on eBay", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      {:ok, view, _html} = live(conn, ~p"/drafts/#{draft}")
      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})
      photo = hd(Drafts.get_draft!(draft.id).photos)
      assert :ok = perform_job(EditPhoto, %{photo_id: photo.id})

      view |> element("#photo-#{photo.id}-edited") |> render_click()
      assert Repo.get!(Photo, photo.id).use_edited == true
      assert Drafts.get_draft!(draft.id).state == "photo_edits_approved"
      assert has_element?(view, "#photo-#{photo.id}-edited[aria-pressed='true'][disabled]")
      assert has_element?(view, "#photo-#{photo.id}-original[disabled]")
      refute has_element?(view, "#redo-edits")
      assert has_element?(view, "#ebay-photo-status", "Replacing on eBay")

      assert :ok = perform_job(ReplaceEbayPhoto, %{photo_id: photo.id})
      assert has_element?(view, "#ebay-photo-status", "Replaced on eBay")
    end

    test "picking the original approves it without eBay", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      {:ok, view, _html} = live(conn, ~p"/drafts/#{draft}")
      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})
      photo = hd(Drafts.get_draft!(draft.id).photos)
      assert :ok = perform_job(EditPhoto, %{photo_id: photo.id})

      view |> element("#photo-#{photo.id}-original") |> render_click()
      assert Repo.get!(Photo, photo.id).use_edited == false
      assert Drafts.get_draft!(draft.id).state == "photo_edits_approved"
      assert has_element?(view, "#photo-#{photo.id}-original[aria-pressed='true'][disabled]")
      refute has_element?(view, "#ebay-photo-status")
      assert [] = all_enqueued(worker: ReplaceEbayPhoto)
    end

    test "a failed eBay replacement shows the error and retries", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=500")
      {:ok, view, _html} = live(conn, ~p"/drafts/#{draft}")
      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})
      photo = hd(Drafts.get_draft!(draft.id).photos)
      assert :ok = perform_job(EditPhoto, %{photo_id: photo.id})
      view |> element("#photo-#{photo.id}-edited") |> render_click()

      assert {:error, _} =
               perform_job(ReplaceEbayPhoto, %{photo_id: photo.id}, attempt: 3, max_attempts: 3)

      assert has_element?(view, "#ebay-photo-status", "eBay returned 500")

      Repo.update_all(from(j in Oban.Job, where: j.state == "available"),
        set: [state: "discarded"]
      )

      view |> element("#retry-ebay-photo") |> render_click()
      assert has_element?(view, "#ebay-photo-status", "Replacing on eBay")
      assert [_] = all_enqueued(worker: ReplaceEbayPhoto, args: %{photo_id: photo.id})
    end

    test "serves the edited photo and refuses a path outside the photo directory", %{conn: conn} do
      {:ok, draft} = Drafts.paste_url(@url)
      assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})
      photo = hd(Drafts.get_draft!(draft.id).photos)

      assert get(conn, ~p"/photos/#{photo}/edited").status == 404

      assert :ok = perform_job(EditPhoto, %{photo_id: photo.id})
      conn = get(build_conn(), ~p"/photos/#{photo}/edited")
      assert conn.status == 200
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")
      assert conn.resp_body == "edited"

      outside = Path.join(System.tmp_dir!(), "flipper-outside-#{photo.id}.png")
      File.write!(outside, "nope")

      photo
      |> Ecto.Changeset.change(edited_path: outside)
      |> Repo.update!()

      assert get(build_conn(), ~p"/photos/#{photo}/edited").status == 404
    end
  end

  defp insert_photo(draft, position) do
    %Photo{}
    |> Photo.changeset(%{
      draft_id: draft.id,
      position: position,
      original_path: "/tmp/flipper-index-#{draft.id}-#{position}.jpg",
      original_content_type: "image/jpeg"
    })
    |> Repo.insert!()
  end
end
