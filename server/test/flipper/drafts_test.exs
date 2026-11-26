defmodule Flipper.DraftsTest do
  use Flipper.DataCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  alias Flipper.Drafts
  alias Flipper.Drafts.Draft
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft
  alias Flipper.Workers.ReplaceEbayPhoto

  @url "https://www.ebay.com/lstng?mode=SellLikeItem&draft_id=5345502780022&ReturnURL=https%3A%2F%2Fwww.ebay.com%2Fsh%2Flst%2Fdrafts"

  test "list_drafts puts the furthest along first, then the oldest listing" do
    undated = listed_draft(1, "photos_taken", nil)
    newer = listed_draft(2, "photos_taken", ~U[2026-11-20 00:00:00.000000Z])
    older = listed_draft(3, "photos_taken", ~U[2026-11-10 00:00:00.000000Z])
    waiting = listed_draft(4, "awaiting_sku", ~U[2026-11-01 00:00:00.000000Z])
    finished = listed_draft(5, "finished", ~U[2026-11-24 00:00:00.000000Z])

    assert Enum.map(Drafts.list_drafts(), & &1.id) ==
             Enum.map([finished, older, newer, undated, waiting], & &1.id)
  end

  test "list_drafts ranks every state" do
    drafts =
      Draft.states()
      |> Enum.with_index(1)
      |> Enum.map(fn {state, number} -> listed_draft(number, state, nil) end)

    assert Enum.map(Drafts.list_drafts(), & &1.id) ==
             drafts |> Enum.reverse() |> Enum.map(& &1.id)
  end

  test "paste_url creates a started draft and enqueues a fetch" do
    assert {:ok, draft} = Drafts.paste_url(@url)
    assert draft.ebay_draft_id == "5345502780022"
    assert draft.state == "started"
    assert draft.title == nil
    assert_enqueued(worker: FetchDraft, args: %{draft_id: draft.id})
  end

  test "paste_url returns the existing draft" do
    assert {:ok, first} = Drafts.paste_url(@url)
    assert {:ok, second} = Drafts.paste_url("https://ebay.com/lstng?draft_id=5345502780022")
    assert first.id == second.id
    assert Repo.aggregate(Draft, :count) == 1
    assert [_] = all_enqueued(worker: FetchDraft)
  end

  test "paste_url accepts draftId" do
    url =
      "https://www.ebay.com/lstng?draftId=5354106131923&mode=SellLikeItem&ReturnURL=https%3A%2F%2Fwww.ebay.com%2Fsh%2Flst%2Fdrafts"

    assert {:ok, draft} = Drafts.paste_url(url)
    assert draft.ebay_draft_id == "5354106131923"
    assert {:ok, again} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=5354106131923")
    assert again.id == draft.id
  end

  test "paste_url rejects a URL without draft_id" do
    assert {:error, changeset} = Drafts.paste_url("https://www.ebay.com/lstng?mode=SellLikeItem")
    assert %{url: [_]} = errors_on(changeset)
    assert Repo.aggregate(Draft, :count) == 0
  end

  test "paste_url rejects a non-eBay host" do
    assert {:error, changeset} = Drafts.paste_url("https://example.com/lstng?draft_id=123")
    assert %{url: [_]} = errors_on(changeset)
    assert Repo.aggregate(Draft, :count) == 0
  end

  test "fetch_from_ebay stores the title and photos" do
    assert {:ok, draft} = Drafts.paste_url(@url)
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    draft = Drafts.get_draft!(draft.id)
    assert draft.title == "Vintage lamp"
    assert draft.sku == "LAMP-1"
    assert draft.state == "photos_taken"
    assert draft.fetch_error == nil
    assert [photo] = draft.photos
    assert photo.position == 1
    assert photo.original_content_type == "image/jpeg"
    assert File.exists?(photo.original_path)
    assert [_] = all_enqueued(worker: EditPhoto, args: %{photo_id: photo.id})

    assert [_] = all_enqueued(worker: FetchDraft, args: %{draft_id: draft.id})
    assert {:ok, again} = Drafts.paste_url(@url)
    assert again.id == draft.id
    assert [_] = all_enqueued(worker: FetchDraft, args: %{draft_id: draft.id})
  end

  test "a draft with a SKU and no photos waits in awaiting_sku" do
    assert {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=0")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "awaiting_sku"
    assert draft.title == "Bare item"
    assert draft.sku == "BARE-1"
    assert draft.photos == []
    assert [] = all_enqueued(worker: EditPhoto)
  end

  test "photos without a SKU wait in awaiting_sku until a refresh finds one" do
    assert {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=11")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "awaiting_sku"
    assert draft.title == "Unlabelled lamp"
    assert draft.sku == nil
    assert draft.photos == []
    assert [] = all_enqueued(worker: EditPhoto)

    Process.put(
      {:ebay_draft, "11"},
      {:ok,
       %{
         title: "Labelled lamp",
         sku: "A-2",
         photo_urls: ["https://i.ebayimg.com/images/g/abc/s-l1600.jpg"]
       }}
    )

    discard_available_jobs()
    assert {:ok, _draft} = Drafts.refresh(draft)
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "photos_taken"
    assert draft.sku == "A-2"
    assert [photo] = draft.photos
    assert_enqueued(worker: EditPhoto, args: %{photo_id: photo.id})
  end

  test "a draft without both photos and a SKU cannot reach photos_taken" do
    assert {:ok, draft} = Drafts.paste_url(@url)
    assert {:error, :invalid_transition} = Drafts.transition(draft, :photos_taken)

    labelled = Repo.update!(Ecto.Changeset.change(draft, sku: "A-1", state: "awaiting_sku"))
    assert {:error, :invalid_transition} = Drafts.transition(labelled, :photos_taken)
    assert [] = all_enqueued(worker: EditPhoto)
  end

  test "the last failed attempt records fetch_error and stays started" do
    assert {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=404")

    assert {:error, _} = perform_job(FetchDraft, %{draft_id: draft.id}, attempt: 1)
    draft = Repo.get!(Draft, draft.id)
    assert draft.fetch_error == nil
    assert draft.state == "started"

    assert {:error, _} = perform_job(FetchDraft, %{draft_id: draft.id}, attempt: 3)
    draft = Repo.get!(Draft, draft.id)
    assert draft.fetch_error == "eBay did not return the draft"
    assert draft.state == "started"
  end

  test "refresh enqueues another fetch and clears fetch_error" do
    assert {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=404")
    assert {:error, _} = perform_job(FetchDraft, %{draft_id: draft.id}, attempt: 3)
    discard_available_jobs()
    assert [] = all_enqueued(worker: FetchDraft, args: %{draft_id: draft.id})

    assert {:ok, draft} = Drafts.refresh(draft)
    assert draft.fetch_error == nil
    assert [_] = all_enqueued(worker: FetchDraft, args: %{draft_id: draft.id})
  end

  test "refresh does nothing when the draft has photos" do
    assert {:ok, draft} = Drafts.paste_url(@url)
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    discard_available_jobs()

    draft = Drafts.get_draft!(draft.id)
    assert {:ok, refreshed} = Drafts.refresh(draft)
    assert refreshed.state == "photos_taken"
    assert [] = all_enqueued(worker: FetchDraft, args: %{draft_id: draft.id})
  end

  test "retry_failed enqueues an eBay job for each failed read and photo replacement" do
    assert {:ok, unread} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=404")
    assert {:error, _} = perform_job(FetchDraft, %{draft_id: unread.id}, attempt: 3)

    assert {:ok, unreplaced} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=500")
    assert :ok = perform_job(FetchDraft, %{draft_id: unreplaced.id})
    [photo] = Drafts.get_draft!(unreplaced.id).photos
    assert :ok = perform_job(EditPhoto, %{photo_id: photo.id})
    assert {:ok, photo} = Drafts.choose_edit(Drafts.get_photo!(photo.id), true)
    assert {:error, _} = perform_job(ReplaceEbayPhoto, %{photo_id: photo.id}, attempt: 3)

    assert {:ok, _healthy} = Drafts.paste_url(@url)
    discard_available_jobs()
    Phoenix.PubSub.subscribe(Flipper.PubSub, "draft:#{unread.id}")

    assert :ok = Drafts.retry_failed()

    assert [_] = all_enqueued(queue: :ebay)
    assert [_] = all_enqueued(queue: :ebay_automated)
    assert_enqueued(queue: :ebay_automated, worker: FetchDraft, args: %{draft_id: unread.id})
    assert_enqueued(queue: :ebay, worker: ReplaceEbayPhoto, args: %{photo_id: photo.id})
    assert Repo.get!(Draft, unread.id).fetch_error == nil
    assert Drafts.get_photo!(photo.id).ebay_error == nil
    assert_received {:draft_changed, _}
  end

  defp listed_draft(ebay_draft_id, state, listed_at) do
    %Draft{}
    |> Draft.create_changeset(to_string(ebay_draft_id))
    |> Ecto.Changeset.change(state: state, listed_at: listed_at)
    |> Repo.insert!()
  end

  defp discard_available_jobs do
    Repo.update_all(
      from(j in Oban.Job, where: j.state == "available"),
      set: [state: "discarded"]
    )
  end
end
