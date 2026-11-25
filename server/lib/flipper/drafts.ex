defmodule Flipper.Drafts do
  import Ecto.Query

  alias Flipper.Drafts.Draft
  alias Flipper.Repo

  def list_drafts do
    Repo.all(from d in Draft, order_by: [desc: d.id])
  end

  def get_draft!(id), do: Repo.get!(Draft, id)

  def paste_url(url) when is_binary(url) do
    case ebay_draft_id(String.trim(url)) do
      {:ok, ebay_draft_id} -> insert_draft(ebay_draft_id)
      :error -> {:error, url_changeset(url)}
    end
  end

  defp insert_draft(ebay_draft_id) do
    %Draft{}
    |> Draft.create_changeset(ebay_draft_id)
    |> Repo.insert()
    |> case do
      {:ok, draft} ->
        {:ok, draft}

      {:error, changeset} ->
        if unique_ebay_draft_id?(changeset) do
          {:ok, Repo.get_by!(Draft, ebay_draft_id: ebay_draft_id)}
        else
          {:error, changeset}
        end
    end
  end

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
    Enum.find_value(["draft_id", "draftId"], fn key ->
      case query[key] do
        id when is_binary(id) -> if id =~ ~r/^\d+$/, do: id
        _ -> nil
      end
    end)
  end

  defp url_changeset(url) do
    {%{}, %{url: :string}}
    |> Ecto.Changeset.cast(%{"url" => url}, [:url])
    |> Ecto.Changeset.add_error(:url, "is not an eBay draft URL")
    |> Map.put(:action, :insert)
  end
end
