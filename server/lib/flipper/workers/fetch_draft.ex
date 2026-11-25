defmodule Flipper.Workers.FetchDraft do
  use Oban.Worker,
    queue: :drafts,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: :incomplete,
      keys: [:draft_id]
    ]

  alias Flipper.Drafts

  @impl true
  def perform(%Oban.Job{args: %{"draft_id" => id}, attempt: attempt, max_attempts: max_attempts}) do
    draft = Drafts.get_draft!(id)

    case Drafts.fetch_from_ebay(draft) do
      :ok ->
        :ok

      {:error, reason} when attempt == max_attempts ->
        Drafts.record_fetch_error(draft, error_message(reason))
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
