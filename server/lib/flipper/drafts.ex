defmodule Flipper.Drafts do
  @moduledoc """
  Lists drafts and creates one from a pasted eBay draft URL.
  """

  import Ecto.Query

  alias Flipper.Drafts.Draft
  alias Flipper.Drafts.Photo
  alias Flipper.Ebay.SellerHub
  alias Flipper.Repo
  alias Flipper.Workers.FetchDraft

  def list_drafts do
    Repo.all(from d in Draft, order_by: [desc: d.id])
  end

  def get_draft!(id) do
    photos = from p in Photo, order_by: p.position

    Draft
    |> Repo.get!(id)
    |> Repo.preload(photos: photos)
  end

  def get_photo!(id), do: Repo.get!(Photo, id)

  def photo_file(%Photo{} = photo) do
    path = Path.expand(photo.original_path)
    root = Path.expand(photo_dir())

    if String.starts_with?(path, root <> "/") and File.regular?(path) do
      {:ok, path, photo.original_content_type}
    else
      :error
    end
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
    update_state(draft, "photos_taken")
  end

  def transition(%Draft{state: "started"} = draft, :awaiting_photos) do
    update_state(draft, "awaiting_photos")
  end

  def transition(%Draft{}, _to), do: {:error, :invalid_transition}

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
    Phoenix.PubSub.broadcast(Flipper.PubSub, "draft:#{id}", {:draft_fetched, id})
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
