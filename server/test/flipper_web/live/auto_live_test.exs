defmodule FlipperWeb.AutoLiveTest do
  use FlipperWeb.ConnCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  import Phoenix.LiveViewTest

  alias Flipper.Drafts
  alias Flipper.Workers.DraftFieldRemovals
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

  test "shows removals before an older photo pick, and approving them shows the next", %{
    conn: conn
  } do
    waiting = fetched_draft(601)
    reviewed = fetched_draft(602)
    edit(waiting)
    draft_removals(reviewed)

    {:ok, view, _html} = live(conn, ~p"/auto")

    assert shown?(view, reviewed, :field_removals)
    refute shown?(view, waiting)

    view
    |> child(reviewed, :field_removals)
    |> element("#field-removals-form")
    |> render_submit()

    assert shown?(view, waiting)
    refute shown?(view, reviewed, :field_removals)
  end

  defp fetched_draft(ebay_draft_id) do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=#{ebay_draft_id}")
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    Drafts.get_draft!(draft.id)
  end

  defp edit(%{photos: [photo]}) do
    :ok = perform_job(EditPhoto, %{photo_id: photo.id})
  end

  defp draft_removals(%{photos: [photo]} = draft) do
    edit(draft)
    {:ok, _photo} = Drafts.choose_edit(Drafts.get_photo!(photo.id), false)
    :ok = perform_job(DraftFieldRemovals, %{draft_id: draft.id})
  end

  defp child_id(draft, kind), do: "auto-#{kind}-#{draft.id}"

  defp child(view, draft, kind \\ :photo_pick) do
    find_live_child(view, child_id(draft, kind))
  end

  defp shown?(view, draft, kind \\ :photo_pick) do
    has_element?(view, "##{child_id(draft, kind)}")
  end

  defp pick_original(view, %{photos: [photo]} = draft) do
    view |> child(draft) |> element("#photo-#{photo.id}-original") |> render_click()
  end
end
