defmodule Flipper.FieldRemovalsTest do
  use Flipper.DataCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  alias Flipper.Drafts
  alias Flipper.Drafts.Draft
  alias Flipper.Drafts.Photo
  alias Flipper.Drafts.Snapshot
  alias Flipper.Workers.DraftFieldRemovals
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft
  alias Flipper.Workers.RemoveEbayFields

  test "the removal draft keeps a snapshot and offers the optional fields" do
    draft = approved_draft("22")

    assert :ok = perform_job(DraftFieldRemovals, %{draft_id: draft.id})
    assert_received {:ebay_draft_read, "22"}

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "field_removals_drafted"
    assert [%Snapshot{modules: %{"ATTRIBUTES" => _}}] = Repo.all(Snapshot)

    assert Enum.map(Drafts.proposed_removals(draft), & &1.name) ==
             ["attributes.Color", "subtitle"]

    assert [] = all_enqueued(worker: RemoveEbayFields)
  end

  test "a valid snapshot is preserved and determines the removal proposals" do
    draft = approved_draft("33")

    original = %{
      "ATTRIBUTES" => %{"attributeList" => []},
      "TITLE" => %{"subtitleField" => %{"value" => "Original"}}
    }

    Repo.insert!(%Snapshot{draft_id: draft.id, modules: original})

    assert :ok = perform_job(DraftFieldRemovals, %{draft_id: draft.id})
    assert [%Snapshot{modules: ^original}] = Repo.all(Snapshot)

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "field_removals_drafted"
    assert [%{name: "subtitle", value: "Original"}] = Drafts.proposed_removals(draft)
  end

  test "a valid read repairs an invalid snapshot and makes its fields available for approval" do
    draft = approved_draft("22")
    snapshot = Repo.insert!(%Snapshot{draft_id: draft.id, modules: %{"TITLE" => %{}}})

    assert :ok = perform_job(DraftFieldRemovals, %{draft_id: draft.id})

    assert %Snapshot{modules: %{"ATTRIBUTES" => %{"attributeList" => [_ | _]}}} =
             Repo.get!(Snapshot, snapshot.id)

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "field_removals_drafted"

    assert Enum.map(Drafts.proposed_removals(draft), & &1.name) == [
             "attributes.Color",
             "subtitle"
           ]
  end

  test "a read without item specifics is not kept as the snapshot" do
    draft = approved_draft("503")

    assert {:error, "eBay draft had no item specifics or title"} =
             perform_job(DraftFieldRemovals, %{draft_id: draft.id})

    assert [] = Repo.all(Snapshot)
    assert Repo.get!(Draft, draft.id).state == "photo_edits_approved"
  end

  test "a draft with nothing to remove finishes" do
    draft = approved_draft("33")

    assert :ok = perform_job(DraftFieldRemovals, %{draft_id: draft.id})
    assert Repo.get!(Draft, draft.id).state == "finished"
  end

  test "only the approved fields are removed, and the draft finishes" do
    draft = reviewed_draft("22")

    assert {:ok, %Draft{state: "field_removals_approved"}} =
             Drafts.approve_field_removals(draft, ["subtitle", "attributes.Brand"])

    assert Repo.get!(Draft, draft.id).approved_removals == ["subtitle"]
    assert_enqueued(queue: :ebay, worker: RemoveEbayFields, args: %{draft_id: draft.id})
    refute_received {:ebay_fields_removed, _, _}

    assert :ok = perform_job(RemoveEbayFields, %{draft_id: draft.id})
    assert_received {:ebay_fields_removed, "22", ["subtitle"]}
    assert Repo.get!(Draft, draft.id).state == "finished"

    assert :ok = perform_job(RemoveEbayFields, %{draft_id: draft.id})
    refute_received {:ebay_fields_removed, _, _}
  end

  test "approval is locked" do
    draft = reviewed_draft("22")
    {:ok, _draft} = Drafts.approve_field_removals(draft, [])

    assert {:error, :invalid_transition} = Drafts.approve_field_removals(draft, ["subtitle"])
    assert Repo.get!(Draft, draft.id).approved_removals == []
  end

  test "nothing is removed from eBay before approval" do
    draft = reviewed_draft("22")

    assert {:error, :invalid_transition} =
             perform_job(RemoveEbayFields, %{draft_id: draft.id})

    refute_received {:ebay_fields_removed, _, _}
  end

  test "a failed read records the error, and a retry drafts again" do
    draft = approved_draft("502")

    assert {:error, _} = perform_job(DraftFieldRemovals, %{draft_id: draft.id}, attempt: 1)
    assert Repo.get!(Draft, draft.id).removal_error == nil

    assert {:error, _} = perform_job(DraftFieldRemovals, %{draft_id: draft.id}, attempt: 3)
    draft = Repo.get!(Draft, draft.id)
    assert draft.removal_error == "eBay returned 502"
    assert draft.state == "photo_edits_approved"

    discard_available_jobs()
    assert {:ok, %Draft{removal_error: nil}} = Drafts.retry_removals(draft)
    assert_enqueued(worker: DraftFieldRemovals, args: %{draft_id: draft.id})
  end

  test "a failed removal records the error, and retry_failed queues it again" do
    draft = reviewed_draft("501")
    {:ok, _draft} = Drafts.approve_field_removals(draft, ["subtitle"])

    assert {:error, _} = perform_job(RemoveEbayFields, %{draft_id: draft.id}, attempt: 3)
    draft = Repo.get!(Draft, draft.id)
    assert draft.removal_error == "eBay returned 501"
    assert draft.state == "field_removals_approved"

    discard_available_jobs()
    assert :ok = Drafts.retry_failed()
    assert Repo.get!(Draft, draft.id).removal_error == nil
    assert_enqueued(worker: RemoveEbayFields, args: %{draft_id: draft.id})
  end

  test "a retry keeps the error while the failed job is still finishing" do
    draft = approved_draft("502")
    assert {:error, _} = perform_job(DraftFieldRemovals, %{draft_id: draft.id}, attempt: 3)
    # perform_job/3 leaves the stored job incomplete, as it is while the worker still runs.
    assert [job] = all_enqueued(worker: DraftFieldRemovals)
    draft = Repo.get!(Draft, draft.id)

    assert {:error, :job_already_queued} = Drafts.retry_removals(draft)
    assert Repo.get!(Draft, draft.id).removal_error == "eBay returned 502"
    assert [^job] = all_enqueued(worker: DraftFieldRemovals)
  end

  test "a draft without an error has nothing to retry" do
    assert {:error, :nothing_to_retry} = Drafts.retry_removals(reviewed_draft("22"))
  end

  # Picking the original needs no photo replacement before the removals.
  defp approved_draft(ebay_draft_id) do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=#{ebay_draft_id}")
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    photo = hd(Drafts.get_draft!(draft.id).photos)
    :ok = perform_job(EditPhoto, %{photo_id: photo.id})
    {:ok, _photo} = Drafts.choose_edit(Repo.get!(Photo, photo.id), false)
    Drafts.get_draft!(draft.id)
  end

  defp reviewed_draft(ebay_draft_id) do
    draft = approved_draft(ebay_draft_id)
    :ok = perform_job(DraftFieldRemovals, %{draft_id: draft.id})
    Drafts.get_draft!(draft.id)
  end

  defp discard_available_jobs do
    Repo.update_all(
      from(j in Oban.Job, where: j.state == "available"),
      set: [state: "discarded"]
    )
  end
end
