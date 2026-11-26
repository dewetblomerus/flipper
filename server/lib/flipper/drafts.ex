defmodule Flipper.Drafts do
  @moduledoc """
  Lists drafts, creates one from a pasted eBay draft URL, edits its photos, replaces the
  approved edit on eBay, and removes the optional fields a person approves.
  """

  import Ecto.Query

  alias Flipper.Drafts.Draft
  alias Flipper.Drafts.Photo
  alias Flipper.Drafts.Snapshot
  alias Flipper.Ebay.SellerHub
  alias Flipper.Ebay.SellerHub.OptionalFields
  alias Flipper.Repo
  alias Flipper.Workers.DraftFieldRemovals
  alias Flipper.Workers.EditPhoto
  alias Flipper.Workers.FetchDraft
  alias Flipper.Workers.RemoveEbayFields
  alias Flipper.Workers.ReplaceEbayPhoto

  @doc """
  Subscribes to every draft's messages.
  """
  def subscribe, do: Phoenix.PubSub.subscribe(Flipper.PubSub, "drafts")

  def list_drafts do
    photos = from p in Photo, order_by: p.position

    Repo.all(from d in Draft, order_by: [desc: d.id], preload: [photos: ^photos])
  end

  def get_draft!(id) do
    photos = from p in Photo, order_by: p.position

    Draft
    |> Repo.get!(id)
    |> Repo.preload(photos: photos)
  end

  def get_photo!(id), do: Repo.get!(Photo, id)

  def photo_file(%Photo{} = photo), do: photo_file(photo, :original)

  def photo_file(%Photo{} = photo, :original) do
    safe_file(photo.original_path, photo.original_content_type)
  end

  def photo_file(%Photo{} = photo, :edited) do
    safe_file(photo.edited_path, photo.edited_content_type)
  end

  def paste_url(url) when is_binary(url) do
    case ebay_draft_id(String.trim(url)) do
      {:ok, ebay_draft_id} -> insert_draft(ebay_draft_id)
      :error -> {:error, url_changeset(url)}
    end
  end

  def change_url(url) when is_binary(url) do
    url = String.trim(url)

    case ebay_draft_id(url) do
      {:ok, _ebay_draft_id} ->
        {%{}, %{url: :string}}
        |> Ecto.Changeset.cast(%{"url" => url}, [:url])

      :error ->
        url_changeset(url)
    end
  end

  def transition(%Draft{state: state} = draft, :photos_taken)
      when state in ["started", "awaiting_photos"] do
    Repo.transaction(fn ->
      case update_state(draft, "photos_taken") do
        {:ok, draft} ->
          enqueue_edits(draft)
          draft

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def transition(%Draft{state: "started"} = draft, :awaiting_photos) do
    update_state(draft, "awaiting_photos")
  end

  def transition(%Draft{state: "photos_taken"} = draft, :photo_edits_drafted) do
    update_state(draft, "photo_edits_drafted")
  end

  def transition(%Draft{state: "photo_edits_drafted"} = draft, :photos_taken) do
    update_state(draft, "photos_taken")
  end

  def transition(%Draft{state: "photo_edits_drafted"} = draft, :photo_edits_approved) do
    update_state(draft, "photo_edits_approved")
  end

  def transition(%Draft{state: "photo_edits_approved"} = draft, :field_removals_drafted) do
    update_state(draft, "field_removals_drafted")
  end

  def transition(%Draft{state: "field_removals_drafted"} = draft, :field_removals_approved) do
    update_state(draft, "field_removals_approved")
  end

  # A draft with no field to remove finishes without a removal approval.
  def transition(%Draft{state: state} = draft, :finished)
      when state in ["photo_edits_approved", "field_removals_approved"] do
    update_state(draft, "finished")
  end

  def transition(%Draft{}, _to), do: {:error, :invalid_transition}

  def edit_photo(%Photo{} = photo) do
    if first_photo?(photo) do
      with :ok <- write_edit(photo),
           :ok <- finish_draft(photo.draft_id) do
        broadcast_changed(photo.draft_id)
        :ok
      end
    else
      :ok
    end
  end

  def redo_edits(%Draft{} = draft) do
    case clear_and_enqueue(draft) do
      {:ok, draft} ->
        broadcast_changed(draft.id)
        {:ok, draft}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def choose_edit(%Photo{edited_path: nil}, _use_edited), do: {:error, :not_edited}

  def choose_edit(%Photo{} = photo, use_edited) when is_boolean(use_edited) do
    case approve(photo, use_edited) do
      {:ok, photo} ->
        broadcast_changed(photo.draft_id)
        {:ok, photo}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def replace_on_ebay(%Photo{replaced_on_ebay_at: %DateTime{}}), do: :ok

  def replace_on_ebay(%Photo{} = photo) do
    photo = Repo.preload(photo, :draft)

    with {:ok, photo} <- upload_edit(photo),
         :ok <- SellerHub.set_first_photo(photo.draft.ebay_draft_id, photo.edited_ebay_url),
         {:ok, photo} <- finish_replacement(photo) do
      broadcast_changed(photo.draft_id)
      :ok
    end
  end

  @doc """
  Keeps a snapshot of the eBay draft and drafts its field removals.
  """
  def draft_field_removals(%Draft{state: "photo_edits_approved"} = draft) do
    with {:ok, modules} <- SellerHub.read_draft(draft.ebay_draft_id),
         {:ok, snapshot} <- keep_snapshot(draft, modules),
         {:ok, filled} <- OptionalFields.filled(snapshot.modules),
         {:ok, _draft} <- advance(draft.id, after_photo(filled), removal_error: nil) do
      broadcast_changed(draft.id)
      :ok
    end
  end

  def draft_field_removals(%Draft{}), do: :ok

  @doc """
  Lists the fields the draft's snapshot offers for removal.
  """
  def proposed_removals(%Draft{id: id}) do
    with %Snapshot{modules: modules} <- Repo.get_by(Snapshot, draft_id: id),
         {:ok, filled} <- OptionalFields.filled(modules) do
      filled
    else
      _ -> []
    end
  end

  def approve_field_removals(%Draft{} = draft, names) when is_list(names) do
    approved = for %{name: name} <- proposed_removals(draft), name in names, do: name

    result =
      Repo.transaction(fn ->
        with {:ok, draft} <- transition(lock_draft(draft.id), :field_removals_approved),
             {:ok, draft} <- update_draft(draft, approved_removals: approved),
             :ok <- insert_job(RemoveEbayFields.new(%{draft_id: draft.id})) do
          draft
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    with {:ok, draft} <- result do
      broadcast_changed(draft.id)
      {:ok, draft}
    end
  end

  def remove_ebay_fields(%Draft{state: "field_removals_approved"} = draft) do
    with :ok <- SellerHub.remove_fields(draft.ebay_draft_id, draft.approved_removals),
         {:ok, _draft} <- advance(draft.id, :finished, removal_error: nil) do
      broadcast_changed(draft.id)
      :ok
    end
  end

  def remove_ebay_fields(%Draft{state: "finished"}), do: :ok
  def remove_ebay_fields(%Draft{}), do: {:error, :invalid_transition}

  def record_removal_error(%Draft{} = draft, reason) when is_binary(reason) do
    {:ok, _draft} = update_draft(draft, removal_error: reason)
    broadcast_changed(draft.id)
    :ok
  end

  def retry_removals(%Draft{id: id}) do
    result =
      Repo.transaction(fn ->
        with %Draft{removal_error: error} = draft when is_binary(error) <- lock_draft(id),
             {:ok, job} <- removal_job(draft),
             {:ok, draft} <- update_draft(draft, removal_error: nil),
             :ok <- insert_job(job) do
          draft
        else
          _ -> Repo.rollback(:nothing_to_retry)
        end
      end)

    with {:ok, draft} <- result do
      broadcast_changed(id)
      {:ok, draft}
    end
  end

  def record_ebay_error(%Photo{} = photo, reason) when is_binary(reason) do
    {:ok, _photo} = update_photo(photo, ebay_error: reason)
    broadcast_changed(photo.draft_id)
    :ok
  end

  def retry_ebay_photo(%Draft{state: "photo_edits_approved", id: id}) do
    case first_photo(id) do
      %Photo{use_edited: true, ebay_error: error} = photo when is_binary(error) ->
        with {:ok, photo} <- clear_error_and_enqueue(photo) do
          broadcast_changed(id)
          {:ok, photo}
        end

      _photo ->
        {:error, :nothing_to_retry}
    end
  end

  def retry_ebay_photo(%Draft{}), do: {:error, :nothing_to_retry}

  def retry_failed do
    Enum.each(failed_fetches(), &retry_fetch/1)
    Enum.each(failed_replacements(), &retry_ebay_photo/1)
    Enum.each(failed_removals(), &retry_removals/1)
  end

  def fetch_from_ebay(%Draft{} = draft) do
    if has_photos?(draft) do
      :ok
    else
      case SellerHub.fetch(draft.ebay_draft_id) do
        {:ok, %{title: title, photo_urls: urls}} ->
          save_fetch(draft, title, urls)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def refresh(%Draft{} = draft) do
    if has_photos?(draft) do
      {:ok, draft}
    else
      with {:ok, draft} <- clear_fetch_error(draft) do
        enqueue_fetch(draft)
      end
    end
  end

  def record_fetch_error(%Draft{} = draft, reason) when is_binary(reason) do
    draft
    |> Ecto.Changeset.change(fetch_error: reason)
    |> Repo.update()

    broadcast_fetched(draft)
    :ok
  end

  def broadcast_fetched(%Draft{id: id}) do
    broadcast(id, {:draft_fetched, id})
  end

  defp save_fetch(draft, title, urls) do
    with {:ok, files} <- download_photos(draft, urls),
         {:ok, draft} <- persist_fetch(draft, title, files) do
      broadcast_fetched(draft)
      :ok
    else
      {:error, reason} ->
        File.rm_rf(draft_dir(draft))
        {:error, reason}
    end
  end

  defp download_photos(draft, urls) do
    File.mkdir_p!(draft_dir(draft))

    urls
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {url, position}, {:ok, files} ->
      case SellerHub.download(url) do
        {:ok, body, type} ->
          path = Path.join(draft_dir(draft), "#{position}#{extension(type)}")
          File.write!(path, body)
          {:cont, {:ok, files ++ [{path, type}]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_fetch(draft, title, files) do
    Repo.transaction(fn ->
      {:ok, draft} =
        draft
        |> Ecto.Changeset.change(title: blank_to_nil(title), fetch_error: nil)
        |> Repo.update()

      Enum.with_index(files, 1)
      |> Enum.each(fn {{path, type}, position} ->
        %Photo{}
        |> Photo.changeset(%{
          draft_id: draft.id,
          position: position,
          original_path: path,
          original_content_type: type
        })
        |> Repo.insert!()
      end)

      state = if files == [], do: :awaiting_photos, else: :photos_taken

      case transition(draft, state) do
        {:ok, draft} -> draft
        {:error, :invalid_transition} when state == :awaiting_photos -> draft
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp update_state(draft, state) do
    draft
    |> Ecto.Changeset.change(state: state)
    |> Repo.update()
  end

  defp enqueue_edits(%Draft{id: id}) do
    case first_photo(id) do
      %Photo{id: photo_id} -> insert_edit_jobs([photo_id])
      nil -> :ok
    end
  end

  defp clear_error_and_enqueue(photo) do
    Repo.transaction(fn ->
      {:ok, photo} = update_photo(photo, ebay_error: nil)
      insert_job(ReplaceEbayPhoto.new(%{photo_id: photo.id}))
      photo
    end)
  end

  defp clear_and_enqueue(%Draft{id: id}) do
    Repo.transaction(fn ->
      case lock_draft(id) do
        %Draft{state: state} = draft when state in ["photos_taken", "photo_edits_drafted"] ->
          clear_first_edit(draft, first_photo(id))

        _draft ->
          Repo.rollback(:invalid_transition)
      end
    end)
  end

  defp approve(%Photo{} = photo, use_edited) do
    Repo.transaction(fn ->
      with {:ok, _draft} <- transition(lock_draft(photo.draft_id), :photo_edits_approved),
           {:ok, photo} <- update_photo(photo, use_edited: use_edited),
           :ok <- enqueue_replace(photo) do
        photo
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # The edit replaces the photo first. Replacing it then drafts the field removals.
  defp enqueue_replace(%Photo{use_edited: true, id: id}) do
    insert_job(ReplaceEbayPhoto.new(%{photo_id: id}))
  end

  defp enqueue_replace(%Photo{draft_id: draft_id}), do: enqueue_removal_draft(draft_id)

  defp enqueue_removal_draft(draft_id) do
    insert_job(DraftFieldRemovals.new(%{draft_id: draft_id}))
  end

  defp finish_replacement(photo) do
    Repo.transaction(fn ->
      with {:ok, photo} <- update_photo(photo, replaced_on_ebay_at: DateTime.utc_now()),
           :ok <- enqueue_removal_draft(photo.draft_id) do
        photo
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp keep_snapshot(%Draft{id: id}, modules) do
    snapshot = %Snapshot{draft_id: id, modules: modules}

    with {:ok, _snapshot} <-
           Repo.insert(snapshot, on_conflict: :nothing, conflict_target: :draft_id) do
      {:ok, Repo.get_by!(Snapshot, draft_id: id)}
    end
  end

  defp after_photo([]), do: :finished
  defp after_photo(_filled), do: :field_removals_drafted

  defp advance(draft_id, to, changes) do
    Repo.transaction(fn ->
      with {:ok, draft} <- transition(lock_draft(draft_id), to),
           {:ok, draft} <- update_draft(draft, changes) do
        draft
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp removal_job(%Draft{state: "photo_edits_approved", id: id}) do
    {:ok, DraftFieldRemovals.new(%{draft_id: id})}
  end

  defp removal_job(%Draft{state: "field_removals_approved", id: id}) do
    {:ok, RemoveEbayFields.new(%{draft_id: id})}
  end

  defp removal_job(%Draft{}), do: :error

  defp update_draft(draft, changes) do
    draft
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
  end

  defp upload_edit(%Photo{edited_ebay_url: url} = photo) when is_binary(url), do: {:ok, photo}

  defp upload_edit(%Photo{} = photo) do
    with {:ok, path, type} <- photo_file(photo, :edited) |> found(),
         {:ok, url} <- SellerHub.upload_photo(photo.draft.ebay_draft_id, path, type) do
      update_photo(photo, edited_ebay_url: url)
    end
  end

  defp found({:ok, path, type}), do: {:ok, path, type}
  defp found(:error), do: {:error, "edited photo is missing"}

  defp update_photo(photo, changes) do
    photo
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
  end

  defp insert_job(changeset) do
    case Oban.insert(changeset) do
      {:ok, _job} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_draft(id) do
    Repo.one!(from d in Draft, where: d.id == ^id, lock: "FOR UPDATE")
  end

  defp clear_first_edit(draft, %Photo{edited_path: path} = photo) when is_binary(path) do
    clear_edit(photo)
    draft = return_to_photos_taken(draft)
    insert_edit_jobs([photo.id])
    draft
  end

  defp clear_first_edit(draft, _photo), do: draft

  defp clear_edit(photo) do
    photo
    |> Ecto.Changeset.change(%{
      edited_path: nil,
      edited_content_type: nil,
      subject_left: nil,
      subject_top: nil,
      subject_width: nil,
      subject_height: nil
    })
    |> Repo.update!()
  end

  defp return_to_photos_taken(draft) do
    case transition(draft, :photos_taken) do
      {:ok, draft} -> draft
      {:error, :invalid_transition} -> draft
    end
  end

  defp insert_edit_jobs(ids) do
    Enum.each(ids, fn photo_id -> insert_job(EditPhoto.new(%{photo_id: photo_id})) end)
  end

  defp write_edit(%Photo{edited_path: path}) when is_binary(path), do: :ok

  defp write_edit(%Photo{} = photo) do
    output = Path.join(Path.dirname(photo.original_path), "#{photo.position}-edited.png")
    photo = Repo.preload(photo, :draft)

    with {:ok, box} <- editor().crop(photo.original_path, output, photo.draft.title) do
      photo
      |> Photo.edit_changeset(%{
        edited_path: output,
        edited_content_type: box.content_type,
        subject_left: box.left,
        subject_top: box.top,
        subject_width: box.width,
        subject_height: box.height
      })
      |> Repo.update()
      |> case do
        {:ok, _photo} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp finish_draft(draft_id) do
    draft_id
    |> lock_and_finish()
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_and_finish(draft_id) do
    Repo.transaction(fn ->
      draft = lock_draft(draft_id)

      if edits_pending?(draft_id) do
        :ok
      else
        finish_transition(draft)
      end
    end)
  end

  defp edits_pending?(draft_id) do
    case first_photo(draft_id) do
      %Photo{edited_path: nil} -> true
      _photo -> false
    end
  end

  defp first_photo?(photo) do
    case first_photo(photo.draft_id) do
      %Photo{id: id} -> id == photo.id
      nil -> false
    end
  end

  defp first_photo(draft_id) do
    Repo.one(from p in Photo, where: p.draft_id == ^draft_id, order_by: p.position, limit: 1)
  end

  defp finish_transition(draft) do
    case transition(draft, :photo_edits_drafted) do
      {:ok, _draft} -> :ok
      {:error, :invalid_transition} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp editor, do: Application.fetch_env!(:flipper, :photo_editor)

  defp safe_file(path, type) when is_binary(path) and is_binary(type) do
    path = Path.expand(path)
    root = Path.expand(photo_dir())

    if String.starts_with?(path, root <> "/") and File.regular?(path) do
      {:ok, path, type}
    else
      :error
    end
  end

  defp safe_file(_path, _type), do: :error

  defp broadcast_changed(draft_id) do
    broadcast(draft_id, {:draft_changed, draft_id})
  end

  defp broadcast(id, message) do
    Phoenix.PubSub.broadcast(Flipper.PubSub, "draft:#{id}", message)
    Phoenix.PubSub.broadcast(Flipper.PubSub, "drafts", message)
  end

  defp insert_draft(ebay_draft_id) do
    %Draft{}
    |> Draft.create_changeset(ebay_draft_id)
    |> Repo.insert()
    |> case do
      {:ok, draft} ->
        enqueue_fetch(draft)

      {:error, changeset} ->
        if unique_ebay_draft_id?(changeset) do
          enqueue_fetch(Repo.get_by!(Draft, ebay_draft_id: ebay_draft_id))
        else
          {:error, changeset}
        end
    end
  end

  defp failed_fetches do
    Repo.all(from d in Draft, where: not is_nil(d.fetch_error), order_by: d.id)
  end

  defp failed_replacements do
    Repo.all(
      from d in Draft,
        join: p in assoc(d, :photos),
        where: not is_nil(p.ebay_error),
        distinct: true,
        order_by: d.id
    )
  end

  defp failed_removals do
    Repo.all(from d in Draft, where: not is_nil(d.removal_error), order_by: d.id)
  end

  defp retry_fetch(draft) do
    with {:ok, draft} <- refresh(draft) do
      broadcast_changed(draft.id)
    end
  end

  defp clear_fetch_error(draft) do
    draft
    |> Ecto.Changeset.change(fetch_error: nil)
    |> Repo.update()
  end

  defp enqueue_fetch(draft) do
    if has_photos?(draft) do
      {:ok, draft}
    else
      %{draft_id: draft.id}
      |> FetchDraft.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> {:ok, draft}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp has_photos?(%Draft{id: id}) do
    Repo.exists?(from p in Photo, where: p.draft_id == ^id)
  end

  defp draft_dir(%Draft{id: id}) do
    Path.join([photo_dir(), "drafts", to_string(id)])
  end

  defp photo_dir, do: Application.fetch_env!(:flipper, :photo_dir)

  defp extension("image/jpeg"), do: ".jpg"
  defp extension("image/png"), do: ".png"
  defp extension("image/gif"), do: ".gif"
  defp extension("image/webp"), do: ".webp"
  defp extension("image/avif"), do: ".avif"
  defp extension("image/heic"), do: ".heic"

  defp blank_to_nil(title) when is_binary(title) do
    case String.trim(title) do
      "" -> nil
      title -> title
    end
  end

  defp blank_to_nil(_), do: nil

  defp unique_ebay_draft_id?(changeset) do
    Enum.any?(changeset.errors, fn
      {:ebay_draft_id, {_message, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp ebay_draft_id(url) do
    uri = URI.parse(url)
    host = uri.host && String.downcase(uri.host)

    with true <- uri.scheme in ["http", "https"],
         true <- host in ["ebay.com", "www.ebay.com"],
         query when is_binary(query) <- uri.query,
         draft_id when is_binary(draft_id) <- draft_id_param(URI.decode_query(query)) do
      {:ok, draft_id}
    else
      _ -> :error
    end
  end

  defp draft_id_param(query) do
    ["draft_id", "draftId"]
    |> Enum.map(&Map.get(query, &1))
    |> Enum.find_value(&digit_id/1)
  end

  defp digit_id(id) when is_binary(id) do
    if id =~ ~r/^\d+$/, do: id
  end

  defp digit_id(_id), do: nil

  defp url_changeset(url) do
    {%{}, %{url: :string}}
    |> Ecto.Changeset.cast(%{"url" => url}, [:url])
    |> Ecto.Changeset.add_error(:url, "is not an eBay draft URL")
    |> Map.put(:action, :insert)
  end
end
