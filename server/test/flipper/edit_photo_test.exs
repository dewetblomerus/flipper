defmodule Flipper.EditPhotoTest do
  use Flipper.DataCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  alias Flipper.Drafts
  alias Flipper.Drafts.Photo
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft

  test "the last edited photo moves the draft to photo_edits_drafted" do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=22")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "photos_taken"
    [first, second] = draft.photos
    assert [_, _] = all_enqueued(worker: EditPhoto)

    original = File.read!(first.original_path)
    assert :ok = perform_job(EditPhoto, %{photo_id: first.id})
    assert_received {:photo_cropped, _}

    draft = Drafts.get_draft!(draft.id)
    assert draft.state == "photos_taken"
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

    assert :ok = perform_job(EditPhoto, %{photo_id: second.id})
    assert Drafts.get_draft!(draft.id).state == "photo_edits_drafted"
  end

  test "an edited photo is not cropped again and can still finish the draft" do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=22")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    [first, second] = Drafts.get_draft!(draft.id).photos
    assert :ok = perform_job(EditPhoto, %{photo_id: first.id})
    assert_received {:photo_cropped, _}

    second
    |> Photo.edit_changeset(%{
      edited_path: second.original_path,
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
end
