defmodule FlipperWeb.AutoLiveTest do
  use FlipperWeb.ConnCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  import Phoenix.LiveViewTest

  alias Flipper.Drafts
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft

  test "has nothing to decide while no draft is waiting on a person", %{conn: conn} do
    draft = fetched_draft(101)

    {:ok, view, _html} = live(conn, ~p"/auto")

    assert has_element?(view, "#auto-empty")
    refute shown?(view, draft)
  end

  test "shows the oldest draft first, and a pick shows the next", %{conn: conn} do
    older = fetched_draft(201)
    newer = fetched_draft(202)
    edit(newer)
    edit(older)

    {:ok, view, _html} = live(conn, ~p"/auto")

    assert shown?(view, older)
    refute shown?(view, newer)

    pick_original(view, older)

    assert shown?(view, newer)
    refute shown?(view, older)

    pick_original(view, newer)

    assert has_element?(view, "#auto-empty")
  end

  test "shows a decision that arrives while the page is open", %{conn: conn} do
    draft = fetched_draft(301)
    {:ok, view, _html} = live(conn, ~p"/auto")

    edit(draft)

    assert shown?(view, draft)
    [photo] = draft.photos
    assert has_element?(child(view, draft), "#photo-#{photo.id}-edited")
  end

  test "keeps the shown draft when an older one starts waiting", %{conn: conn} do
    older = fetched_draft(401)
    newer = fetched_draft(402)
    edit(newer)
    {:ok, view, _html} = live(conn, ~p"/auto")

    edit(older)

    assert shown?(view, newer)
    refute shown?(view, older)

    pick_original(view, newer)

    assert shown?(view, older)
  end

  test "redo edit moves on to the next draft", %{conn: conn} do
    first = fetched_draft(501)
    second = fetched_draft(502)
    edit(first)
    edit(second)
    {:ok, view, _html} = live(conn, ~p"/auto")

    view |> child(first) |> element("#redo-edits") |> render_click()

    assert shown?(view, second)
    refute shown?(view, first)
  end

  defp fetched_draft(ebay_draft_id) do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=#{ebay_draft_id}")
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    Drafts.get_draft!(draft.id)
  end

  defp edit(%{photos: [photo]}) do
    :ok = perform_job(EditPhoto, %{photo_id: photo.id})
  end

  defp child_id(draft), do: "auto-photo_pick-#{draft.id}"

  defp child(view, draft), do: find_live_child(view, child_id(draft))

  defp shown?(view, draft), do: has_element?(view, "##{child_id(draft)}")

  defp pick_original(view, %{photos: [photo]} = draft) do
    view |> child(draft) |> element("#photo-#{photo.id}-original") |> render_click()
  end
end
