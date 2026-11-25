defmodule Flipper.DraftsTest do
  use Flipper.DataCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  alias Flipper.Drafts
  alias Flipper.Drafts.Draft
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft

  @url "https://www.ebay.com/lstng?mode=SellLikeItem&draft_id=5345502780022&ReturnURL=https%3A%2F%2Fwww.ebay.com%2Fsh%2Flst%2Fdrafts"

  test "list_drafts returns newest first" do
    assert {:ok, older} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=1")
    assert {:ok, newer} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=2")
    assert Enum.map(Drafts.list_drafts(), & &1.id) == [newer.id, older.id]
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

  test "fetch_from_ebay with no photos moves the draft to awaiting_photos" do
    assert {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=0")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    draft = Drafts.get_draft!(draft.id)
    assert draft.title == "Bare item"
    assert draft.state == "awaiting_photos"
    assert draft.photos == []
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

  defp discard_available_jobs do
    Repo.update_all(
      from(j in Oban.Job, where: j.state == "available"),
      set: [state: "discarded"]
    )
  end
end
