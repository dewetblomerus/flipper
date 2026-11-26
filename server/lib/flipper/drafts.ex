defmodule Flipper.Drafts do
  @moduledoc """
  Lists drafts, creates them from a pasted eBay draft URL or the Seller Hub drafts list,
  edits their photos, replaces the approved edit on eBay, and removes the optional fields a
  person approves.
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
  alias Flipper.Workers.ImportDrafts
  alias Flipper.Workers.RemoveEbayFields
  alias Flipper.Workers.ReplaceEbayPhoto

  # The job states a person's request can move out of the paced queue.
  @waiting [available: [:queue], scheduled: [:queue], retryable: [:queue]]

  # The job states with nothing left to run.
  @ended ["completed", "cancelled", "discarded"]
  @lost_write "The eBay job ended before it finished."

  @doc """
  Subscribes to every draft's messages.
  """
  def subscribe, do: Phoenix.PubSub.subscribe(Flipper.PubSub, "drafts")

  @doc """
  Subscribes to the result of each drafts list import.
  """
  def subscribe_import, do: Phoenix.PubSub.subscribe(Flipper.PubSub, "drafts_import")

  def broadcast_import(result) do
    Phoenix.PubSub.broadcast(Flipper.PubSub, "drafts_import", {:drafts_import, result})
  end

  @doc """
  Queues the import a person asked for. It takes over one still waiting in the paced queue.
  """
  def refresh_list do
    %{}
    |> ImportDrafts.new(queue: :ebay, replace: @waiting)
    |> Oban.insert()
  end

  @doc """
  Lists drafts: furthest along first, then the oldest eBay listing.
  """
  def list_drafts do
    photos = from p in Photo, order_by: p.position

    Repo.all(
      from d in Draft,
        order_by: [
          desc: fragment("array_position(?::text[], ?::text)", ^Draft.states(), d.state),
          asc_nulls_last: d.listed_at,
          asc: d.id
        ],
        preload: [photos: ^photos]
    )
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

  # Photo work starts only once the draft has both photos and a SKU.
  def transition(%Draft{state: state} = draft, :photos_taken)
      when state in ["started", "awaiting_sku"] do
    if is_binary(draft.sku) and has_photos?(draft) do
      start_photo_work(draft)
    else
      {:error, :invalid_transition}
    end
  end

  def transition(%Draft{state: "started"} = draft, :awaiting_sku) do
    update_state(draft, "awaiting_sku")
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
         {:ok, _filled} <- OptionalFields.filled(modules),
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
             :ok <- insert_new_job(job) do
          draft
        else
          {:error, reason} -> Repo.rollback(reason)
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

  @doc """
  Records an error on each approved eBay write with no job left to run it.
  """
  def record_lost_ebay_writes do
    Enum.each(lost_replacements(), &record_ebay_error(&1, @lost_write))
    Enum.each(lost_removals(), &record_removal_error(&1, @lost_write))
  end

  @doc """
  Queues each failed eBay job again. Reads are paced, since there can be many.
  """
  def retry_failed do
    Enum.each(failed_fetches(), &retry_fetch/1)
    Enum.each(failed_replacements(), &retry_ebay_photo/1)
    Enum.each(failed_removals(), &retry_removals/1)
  end

  def fetch_from_ebay(%Draft{} = draft) do
    if has_photos?(draft) do
      :ok
    else
      with {:ok, read} <- SellerHub.fetch(draft.ebay_draft_id) do
        save_fetch(draft, read)
      end
    end
  end

  def refresh(%Draft{} = draft), do: reread(draft, :ebay)

  @doc """
  Adds each unknown draft on the Seller Hub list. A draft is read once the list shows it
  with both a SKU and a photo. Until then it waits in `awaiting_sku`.
  """
  def import_from_ebay do
    with {:ok, listed} <- SellerHub.drafts() do
      known = known_drafts(listed)
      Enum.each(listed, &import_listed(&1, known[&1.ebay_draft_id]))
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

  defp known_drafts(listed) do
    ids = Enum.map(listed, & &1.ebay_draft_id)

    from(d in Draft, where: d.ebay_draft_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.ebay_draft_id, &1})
  end

  defp import_listed(listed, nil), do: add_listed(listed)

  defp import_listed(listed, %Draft{state: "awaiting_sku"} = draft) do
    {:ok, draft} = update_draft(draft, listed_fields(listed) ++ listed_age(listed))

    if ready?(listed) do
      {:ok, _draft} = Repo.transact(fn -> queue_due_read(lock_draft(draft.id)) end)
    end
  end

  defp import_listed(listed, draft) do
    {:ok, _draft} = update_draft(draft, listed_age(listed))
  end

  # The draft and its read are saved together, so no imported draft is left unread.
  defp add_listed(listed) do
    changeset =
      %Draft{}
      |> Draft.create_changeset(listed.ebay_draft_id)
      |> Ecto.Changeset.change(listed_fields(listed) ++ listed_age(listed))

    {:ok, _result} =
      Repo.transact(fn ->
        case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :ebay_draft_id) do
          # A paste added it first.
          {:ok, %Draft{id: nil}} -> {:ok, :already_added}
          {:ok, draft} -> start_listed(draft, listed)
          {:error, reason} -> {:error, reason}
        end
      end)
  end

  defp start_listed(draft, listed) do
    if ready?(listed) do
      queue_import_read(draft)
    else
      transition(draft, :awaiting_sku)
    end
  end

  # Checked on the locked row, since another import can queue the read after this one
  # loads its drafts.
  defp queue_due_read(%Draft{state: "awaiting_sku"} = draft) do
    if due?(draft), do: queue_import_read(draft), else: {:ok, draft}
  end

  defp queue_due_read(draft), do: {:ok, draft}

  defp queue_import_read(draft) do
    with {:ok, draft} <- update_draft(draft, import_read_at: DateTime.utc_now()) do
      enqueue_fetch(draft, :ebay_automated, retry: false)
    end
  end

  defp listed_fields(%{title: title, sku: sku}) do
    [title: blank_to_nil(title), sku: blank_to_nil(sku)]
  end

  # A date the list didn't give leaves the one already saved.
  defp listed_age(%{listed_at: nil}), do: []
  defp listed_age(%{listed_at: listed_at}), do: [listed_at: listed_at]

  defp ready?(%{sku: sku, photo?: photo?}), do: photo? and blank_to_nil(sku) != nil

  # A failed read waits for a person. The list can show a draft as ready when its page
  # doesn't, so an import queues a draft's read at most once a day.
  defp due?(%Draft{fetch_error: nil, import_read_at: nil}), do: true

  defp due?(%Draft{fetch_error: nil, import_read_at: at}) do
    DateTime.diff(DateTime.utc_now(), at, :hour) >= 24
  end

  defp due?(_draft), do: false

  # Photos are downloaded only for a draft that also has a SKU.
  defp save_fetch(draft, %{title: title, sku: sku, photo_urls: urls}) do
    urls = if sku, do: urls, else: []

    fields = [title: blank_to_nil(title), sku: sku, fetch_error: nil]

    with {:ok, files} <- download_photos(draft, urls),
         {:ok, draft} <- persist_fetch(draft, fields, files) do
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

  defp persist_fetch(draft, fields, files) do
    Repo.transaction(fn ->
      {:ok, draft} = update_draft(draft, fields)

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

      state = if files == [], do: :awaiting_sku, else: :photos_taken

      case transition(draft, state) do
        {:ok, draft} -> draft
        {:error, :invalid_transition} when state == :awaiting_sku -> draft
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp update_state(draft, state) do
    draft
    |> Ecto.Changeset.change(state: state)
    |> Repo.update()
  end

  defp start_photo_work(draft) do
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
    Repo.transact(fn ->
      # Serialize snapshot creation and repair so a retry always keeps a valid snapshot.
      lock_draft(id)

      case Repo.get_by(Snapshot, draft_id: id) do
        nil -> Repo.insert(%Snapshot{draft_id: id, modules: modules})
        %Snapshot{} = snapshot -> repair_snapshot(snapshot, modules)
      end
    end)
  end

  defp repair_snapshot(snapshot, modules) do
    case OptionalFields.filled(snapshot.modules) do
      {:ok, _filled} -> {:ok, snapshot}
      {:error, _reason} -> snapshot |> Ecto.Changeset.change(modules: modules) |> Repo.update()
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

  defp removal_job(%Draft{}), do: :nothing_to_retry

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

  # The failing job records its error before it finishes, and blocks a new one until then.
  defp insert_new_job(changeset) do
    case Oban.insert(changeset) do
      {:ok, %Oban.Job{conflict?: false}} -> :ok
      {:ok, %Oban.Job{conflict?: true}} -> {:error, :job_already_queued}
      {:error, reason} -> {:error, reason}
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
        enqueue_fetch(draft, :ebay)

      {:error, changeset} ->
        if unique_ebay_draft_id?(changeset) do
          enqueue_fetch(Repo.get_by!(Draft, ebay_draft_id: ebay_draft_id), :ebay)
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

  defp lost_replacements do
    jobs =
      from j in live_jobs(ReplaceEbayPhoto),
        where: fragment("(?->>'photo_id')::bigint", j.args) == parent_as(:photo).id

    Repo.all(
      from p in Photo,
        as: :photo,
        join: d in assoc(p, :draft),
        where: d.state == "photo_edits_approved" and p.use_edited,
        where: is_nil(p.replaced_on_ebay_at) and is_nil(p.ebay_error),
        where: not exists(jobs)
    )
  end

  defp lost_removals do
    jobs =
      from j in live_jobs(RemoveEbayFields),
        where: fragment("(?->>'draft_id')::bigint", j.args) == parent_as(:draft).id

    Repo.all(
      from d in Draft,
        as: :draft,
        where: d.state == "field_removals_approved" and is_nil(d.removal_error),
        where: not exists(jobs)
    )
  end

  defp live_jobs(worker) do
    from j in Oban.Job,
      where: j.worker == ^Oban.Worker.to_string(worker) and j.state not in @ended
  end

  defp retry_fetch(draft) do
    with {:ok, draft} <- reread(draft, :ebay_automated) do
      broadcast_changed(draft.id)
    end
  end

  defp reread(draft, queue) do
    if has_photos?(draft) do
      {:ok, draft}
    else
      with {:ok, draft} <- clear_fetch_error(draft) do
        enqueue_fetch(draft, queue)
      end
    end
  end

  defp clear_fetch_error(draft) do
    draft
    |> Ecto.Changeset.change(fetch_error: nil)
    |> Repo.update()
  end

  defp enqueue_fetch(draft, queue, opts \\ []) do
    if has_photos?(draft) do
      {:ok, draft}
    else
      draft
      |> fetch_job(queue)
      |> Oban.insert(opts)
      |> case do
        {:ok, _job} -> {:ok, draft}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # A person's read takes over one still waiting in the paced queue.
  defp fetch_job(%Draft{id: id}, :ebay) do
    FetchDraft.new(%{draft_id: id}, replace: @waiting)
  end

  defp fetch_job(%Draft{id: id}, :ebay_automated) do
    FetchDraft.new(%{draft_id: id}, queue: :ebay_automated)
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
