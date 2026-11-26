defmodule Flipper.EditPhotoTest do
  use Flipper.DataCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  import Ecto.Query

  alias Flipper.Drafts
  alias Flipper.Drafts.Photo
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft

  test "the first photo is cropped and finishes the draft" do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=22")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "photos_taken"
    [first, second] = draft.photos
    assert [_] = all_enqueued(worker: EditPhoto, args: %{photo_id: first.id})
    assert [] = all_enqueued(worker: EditPhoto, args: %{photo_id: second.id})

    original = File.read!(first.original_path)
    assert :ok = perform_job(EditPhoto, %{photo_id: second.id})
    refute_received {:photo_cropped, _}
    assert Drafts.get_draft!(draft.id).state == "photos_taken"

    assert :ok = perform_job(EditPhoto, %{photo_id: first.id})
    assert_received {:photo_cropped, _}

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "photo_edits_drafted"
    assert File.read!(first.original_path) == original

    edited = Enum.find(draft.photos, &(&1.id == first.id))
    assert edited.edited_content_type == "image/png"
    assert edited.subject_left == 1
    assert edited.subject_top == 2
    assert edited.subject_width == 3
    assert edited.subject_height == 4
    assert String.ends_with?(edited.edited_path, "/1-edited.png")
    assert File.read!(edited.edited_path) == "edited"
    assert edited.use_edited == nil

    untouched = Enum.find(draft.photos, &(&1.id == second.id))
    assert untouched.edited_path == nil
  end

  test "an edited first photo is not cropped again and can still finish the draft" do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=22")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    [first, _second] = Drafts.get_draft!(draft.id).photos

    first
    |> Photo.edit_changeset(%{
      edited_path: first.original_path,
      edited_content_type: "image/png",
      subject_left: 0,
      subject_top: 0,
      subject_width: 1,
      subject_height: 1
    })
    |> Repo.update!()

    assert Drafts.get_draft!(draft.id).state == "photos_taken"
    assert :ok = perform_job(EditPhoto, %{photo_id: first.id})
    refute_received {:photo_cropped, _}
    assert Drafts.get_draft!(draft.id).state == "photo_edits_drafted"
  end

  test "redo edit clears the first crop and enqueues that job again" do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=22")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    [first, second] = Drafts.get_draft!(draft.id).photos
    assert :ok = perform_job(EditPhoto, %{photo_id: first.id})
    assert Drafts.get_draft!(draft.id).state == "photo_edits_drafted"
    discard_available_jobs()

    assert {:ok, draft} = Drafts.redo_edits(draft)
    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "photos_taken"
    assert Enum.all?(draft.photos, &is_nil(&1.edited_path))
    assert [_] = all_enqueued(worker: EditPhoto, args: %{photo_id: first.id})
    assert [] = all_enqueued(worker: EditPhoto, args: %{photo_id: second.id})

    assert :ok = perform_job(EditPhoto, %{photo_id: first.id})
    assert Drafts.get_draft!(draft.id).state == "photo_edits_drafted"
    assert Repo.get!(Photo, second.id).edited_path == nil
  end

  defp discard_available_jobs do
    Repo.update_all(from(j in Oban.Job, where: j.state == "available"), set: [state: "discarded"])
  end
end
