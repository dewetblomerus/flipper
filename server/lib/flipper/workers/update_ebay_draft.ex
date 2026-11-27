defmodule Flipper.Workers.UpdateEbayDraft do
  @moduledoc """
  Saves the approved photo and field removals to the eBay draft and finishes it.
  """

  alias Flipper.Workers.EbayPriority

  use Oban.Worker,
    queue: :ebay_cookie_requests,
    priority: EbayPriority.write(),
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

    case Drafts.update_on_ebay(draft) do
      :ok ->
        :ok

      {:error, reason} when attempt == max_attempts ->
        Drafts.record_ebay_error(Drafts.get_draft!(id), error_message(reason))
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
