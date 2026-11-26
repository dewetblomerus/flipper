defmodule Flipper.ReplaceEbayPhotoTest do
  use Flipper.DataCase, async: true
  use Oban.Testing, repo: Flipper.Repo

  alias Flipper.Drafts
  alias Flipper.Drafts.Photo
  alias Flipper.Workers.DraftFieldRemovals
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft
  alias Flipper.Workers.ReplaceEbayPhoto

  @new_url "https://i.ebayimg.com/images/g/new/s-l1600.png"

  test "approving the edit enqueues the eBay job" do
    {draft, photo} = edited_draft("22")

    assert {:ok, %Photo{use_edited: true}} = Drafts.choose_edit(photo, true)
    assert Drafts.get_draft!(draft.id).state == "photo_edits_approved"
    assert [_] = all_enqueued(worker: ReplaceEbayPhoto, args: %{photo_id: photo.id})
  end

  test "approving the original replaces no photo and drafts the field removals" do
    {draft, photo} = edited_draft("22")

    assert {:ok, %Photo{use_edited: false}} = Drafts.choose_edit(photo, false)
    assert Drafts.get_draft!(draft.id).state == "photo_edits_approved"
    assert [] = all_enqueued(worker: ReplaceEbayPhoto)
    assert [_] = all_enqueued(worker: DraftFieldRemovals, args: %{draft_id: draft.id})
  end

  test "an approved choice is locked and its edit is not redone" do
    {draft, photo} = edited_draft("22")
    {:ok, _photo} = Drafts.choose_edit(photo, false)

    assert {:error, :invalid_transition} = Drafts.choose_edit(photo, true)
    assert Repo.get!(Photo, photo.id).use_edited == false
    assert {:error, :invalid_transition} = Drafts.redo_edits(Drafts.get_draft!(draft.id))
    assert Repo.get!(Photo, photo.id).edited_path
  end

  test "the job uploads the edit and makes it the first photo" do
    {draft, photo} = edited_draft("22")
    {:ok, _photo} = Drafts.choose_edit(photo, true)

    assert :ok = perform_job(ReplaceEbayPhoto, %{photo_id: photo.id})
    assert_received {:ebay_photo_uploaded, "22", path, "image/png"}
    assert path == Path.expand(photo.edited_path)
    assert_received {:ebay_first_photo_set, "22", @new_url}

    photo = Repo.get!(Photo, photo.id)
    assert photo.edited_ebay_url == @new_url
    assert %DateTime{} = photo.replaced_on_ebay_at
    assert Drafts.get_draft!(draft.id).state == "photo_edits_approved"
    assert [_] = all_enqueued(worker: DraftFieldRemovals, args: %{draft_id: draft.id})

    assert :ok = perform_job(ReplaceEbayPhoto, %{photo_id: photo.id})
    refute_received {:ebay_photo_uploaded, _, _, _}
    refute_received {:ebay_first_photo_set, _, _}
  end

  test "the last failed attempt records the error, and a retry reuses the upload" do
    {draft, photo} = edited_draft("500")
    {:ok, _photo} = Drafts.choose_edit(photo, true)
    assert [] = all_enqueued(worker: DraftFieldRemovals)

    assert {:error, "eBay returned 500"} =
             perform_job(ReplaceEbayPhoto, %{photo_id: photo.id}, attempt: 1, max_attempts: 3)

    assert Repo.get!(Photo, photo.id).ebay_error == nil
    assert_received {:ebay_photo_uploaded, _, _, _}

    assert {:error, _} =
             perform_job(ReplaceEbayPhoto, %{photo_id: photo.id}, attempt: 3, max_attempts: 3)

    refute_received {:ebay_photo_uploaded, _, _, _}
    photo = Repo.get!(Photo, photo.id)
    assert photo.ebay_error == "eBay returned 500"
    assert photo.edited_ebay_url == @new_url
    assert photo.replaced_on_ebay_at == nil

    assert {:ok, %Photo{ebay_error: nil}} = Drafts.retry_ebay_photo(Drafts.get_draft!(draft.id))
  end

  defp edited_draft(ebay_draft_id) do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=#{ebay_draft_id}")
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    photo = hd(Drafts.get_draft!(draft.id).photos)
    :ok = perform_job(EditPhoto, %{photo_id: photo.id})
    {draft, Repo.get!(Photo, photo.id)}
  end
end
