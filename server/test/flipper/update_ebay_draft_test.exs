defmodule Flipper.UpdateEbayDraftTest do
  use Flipper.DataCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  alias Flipper.Drafts
  alias Flipper.Drafts.Draft
  alias Flipper.Drafts.Photo
  alias Flipper.Drafts.Snapshot
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft
  alias Flipper.Workers.RecordLostEbayWrites
  alias Flipper.Workers.UpdateEbayDraft

  @new_url "https://i.ebayimg.com/images/g/new/s-l1600.png"
  @removals ["attributes.Color", "subtitle"]

  test "the fetch keeps a snapshot and drafts the optional fields" do
    {draft, _photo} = edited_draft("22")

    assert [%Snapshot{modules: %{"ATTRIBUTES" => _}}] = Repo.all(Snapshot)
    assert Enum.map(Drafts.proposed_removals(draft), & &1.name) == @removals
  end

  test "a read without item specifics fails and saves nothing" do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=503")

    assert {:error, "eBay draft had no item specifics or title"} =
             perform_job(FetchDraft, %{draft_id: draft.id})

    assert [] = Repo.all(Snapshot)
    assert %Draft{state: "started"} = Repo.get!(Draft, draft.id)
    assert Drafts.get_draft!(draft.id).photos == []
  end

  test "a later read replaces the snapshot" do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=11")
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    assert length(Drafts.proposed_removals(draft)) == 2

    modules = %{"ATTRIBUTES" => %{"attributeList" => []}, "TITLE" => %{}}
    read = %{title: "Lamp", sku: "A-2", photo_urls: [], modules: modules}
    Process.put({:ebay_draft, "11"}, {:ok, read})
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    assert [%Snapshot{modules: ^modules}] = Repo.all(Snapshot)
  end

  test "picking a photo approves every removal and queues one write" do
    {draft, photo} = edited_draft("22")

    assert {:ok, %Photo{use_edited: true}} = Drafts.choose_edit(photo, true)

    draft = Repo.get!(Draft, draft.id)
    assert draft.state == "field_removals_approved"
    assert draft.approved_removals == @removals

    assert [%{queue: "ebay_cookie_requests", priority: 0}] =
             all_enqueued(worker: UpdateEbayDraft)

    assert_enqueued(worker: UpdateEbayDraft, args: %{draft_id: draft.id})
    refute_received {:ebay_draft_updated, _, _}
  end

  test "the job saves the edit and the removals together, and finishes the draft" do
    {draft, photo} = edited_draft("22")
    {:ok, _photo} = Drafts.choose_edit(photo, true)

    assert :ok = perform_job(UpdateEbayDraft, %{draft_id: draft.id})
    assert_received {:ebay_photo_uploaded, "22", path, "image/png"}
    assert path == Path.expand(photo.edited_path)
    assert_received {:ebay_draft_updated, "22", %{photo: @new_url, remove: @removals}}

    photo = Repo.get!(Photo, photo.id)
    assert photo.edited_ebay_url == @new_url
    assert %DateTime{} = photo.replaced_on_ebay_at
    assert Repo.get!(Draft, draft.id).state == "finished"

    assert :ok = perform_job(UpdateEbayDraft, %{draft_id: draft.id})
    refute_received {:ebay_photo_uploaded, _, _, _}
    refute_received {:ebay_draft_updated, _, _}
  end

  test "picking the original saves only the removals" do
    {draft, photo} = edited_draft("22")
    {:ok, _photo} = Drafts.choose_edit(photo, false)

    assert :ok = perform_job(UpdateEbayDraft, %{draft_id: draft.id})
    refute_received {:ebay_photo_uploaded, _, _, _}
    assert_received {:ebay_draft_updated, "22", %{photo: nil, remove: @removals}}
    assert Repo.get!(Photo, photo.id).replaced_on_ebay_at == nil
    assert Repo.get!(Draft, draft.id).state == "finished"
  end

  test "a draft with nothing to remove saves only the photo" do
    {draft, photo} = edited_draft("33")
    {:ok, _photo} = Drafts.choose_edit(photo, true)

    assert :ok = perform_job(UpdateEbayDraft, %{draft_id: draft.id})
    assert_received {:ebay_draft_updated, "33", %{photo: @new_url, remove: []}}
    assert Repo.get!(Draft, draft.id).state == "finished"
  end

  test "an approved choice is locked and its edit is not redone" do
    {draft, photo} = edited_draft("22")
    {:ok, _photo} = Drafts.choose_edit(photo, false)

    assert {:error, :invalid_transition} = Drafts.choose_edit(photo, true)
    assert Repo.get!(Photo, photo.id).use_edited == false
    assert {:error, :invalid_transition} = Drafts.redo_edits(Drafts.get_draft!(draft.id))
    assert Repo.get!(Photo, photo.id).edited_path
  end

  test "a pick without drafted removals approves nothing" do
    {draft, photo} = edited_draft("22")
    Repo.delete_all(Snapshot)

    assert {:error, :removals_not_drafted} = Drafts.choose_edit(photo, true)
    assert Repo.get!(Draft, draft.id).state == "photo_edits_drafted"
    assert Repo.get!(Photo, photo.id).use_edited == nil
    assert [] = all_enqueued(worker: UpdateEbayDraft)
  end

  test "nothing is written to eBay before approval" do
    {draft, _photo} = edited_draft("22")

    assert {:error, :invalid_transition} =
             perform_job(UpdateEbayDraft, %{draft_id: draft.id})

    refute_received {:ebay_draft_updated, _, _}
  end

  test "the last failed attempt records the error, and a retry reuses the upload" do
    {draft, photo} = edited_draft("500")
    {:ok, _photo} = Drafts.choose_edit(photo, true)

    assert {:error, "eBay returned 500"} =
             perform_job(UpdateEbayDraft, %{draft_id: draft.id}, attempt: 1)

    assert Repo.get!(Draft, draft.id).ebay_error == nil
    assert_received {:ebay_photo_uploaded, _, _, _}

    assert {:error, _} = perform_job(UpdateEbayDraft, %{draft_id: draft.id}, attempt: 3)
    refute_received {:ebay_photo_uploaded, _, _, _}

    draft = Repo.get!(Draft, draft.id)
    assert draft.ebay_error == "eBay returned 500"
    assert draft.state == "field_removals_approved"
    photo = Repo.get!(Photo, photo.id)
    assert photo.edited_ebay_url == @new_url
    assert photo.replaced_on_ebay_at == nil

    discard_available_jobs()
    assert {:ok, %Draft{ebay_error: nil}} = Drafts.retry_ebay(draft)
    assert_enqueued(worker: UpdateEbayDraft, args: %{draft_id: draft.id})
  end

  test "a retry keeps the error while the failed job is still finishing" do
    draft = approved_draft("500")
    assert {:error, _} = perform_job(UpdateEbayDraft, %{draft_id: draft.id}, attempt: 3)
    # perform_job/3 leaves the stored job incomplete, as it is while the worker still runs.
    assert [job] = all_enqueued(worker: UpdateEbayDraft)

    assert {:error, :job_already_queued} = Drafts.retry_ebay(draft)
    assert Repo.get!(Draft, draft.id).ebay_error == "eBay returned 500"
    assert [^job] = all_enqueued(worker: UpdateEbayDraft)
  end

  test "a draft without an error has nothing to retry" do
    assert {:error, :nothing_to_retry} = Drafts.retry_ebay(approved_draft("22"))
  end

  test "a write whose job ends without an error becomes retryable" do
    draft = approved_draft("22")

    assert :ok = perform_job(RecordLostEbayWrites, %{})
    assert Repo.get!(Draft, draft.id).ebay_error == nil

    discard_available_jobs()
    assert :ok = perform_job(RecordLostEbayWrites, %{})

    draft = Repo.get!(Draft, draft.id)
    assert is_binary(draft.ebay_error)
    assert {:ok, %Draft{ebay_error: nil}} = Drafts.retry_ebay(draft)
    assert_enqueued(worker: UpdateEbayDraft, args: %{draft_id: draft.id})
  end

  test "a finished write is not a lost one" do
    draft = approved_draft("22")
    :ok = perform_job(UpdateEbayDraft, %{draft_id: draft.id})
    Repo.update_all(Oban.Job, set: [state: "completed"])

    assert :ok = perform_job(RecordLostEbayWrites, %{})
    assert Repo.get!(Draft, draft.id).ebay_error == nil
  end

  defp edited_draft(ebay_draft_id) do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=#{ebay_draft_id}")
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    photo = hd(Drafts.get_draft!(draft.id).photos)
    :ok = perform_job(EditPhoto, %{photo_id: photo.id})
    {Drafts.get_draft!(draft.id), Repo.get!(Photo, photo.id)}
  end

  defp approved_draft(ebay_draft_id) do
    {draft, photo} = edited_draft(ebay_draft_id)
    {:ok, _photo} = Drafts.choose_edit(photo, false)
    Drafts.get_draft!(draft.id)
  end

  defp discard_available_jobs do
    Repo.update_all(
      from(j in Oban.Job, where: j.state == "available"),
      set: [state: "discarded"]
    )
  end
end
