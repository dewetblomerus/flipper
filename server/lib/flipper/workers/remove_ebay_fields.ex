defmodule Flipper.Workers.RemoveEbayFields do
  @moduledoc """
  Removes the approved fields from the eBay draft and finishes it.
  """

  use Oban.Worker,
    queue: :ebay,
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

    case Drafts.remove_ebay_fields(draft) do
      :ok ->
        :ok

      {:error, reason} when attempt == max_attempts ->
        Drafts.record_removal_error(Drafts.get_draft!(id), error_message(reason))
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
