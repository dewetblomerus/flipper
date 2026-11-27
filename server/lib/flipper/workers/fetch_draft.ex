defmodule Flipper.Workers.FetchDraft do
  @moduledoc """
  Loads a draft's title, SKU, and photos from Seller Hub. A draft has one read at a time.
  """

  alias Flipper.Workers.EbayPriority

  use Oban.Worker,
    queue: :ebay_cookie_requests,
    priority: EbayPriority.person_read(),
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: :incomplete,
      keys: [:draft_id]
    ]

  alias Flipper.Drafts
  alias Flipper.Ebay.Session

  @unattended EbayPriority.unattended_read()

  @impl true
  def perform(%Oban.Job{args: %{"draft_id" => id}} = job) do
    draft = Drafts.get_draft!(id)

    if blocked?(job, draft) do
      Drafts.record_fetch_error(draft, "eBay cookie needs attention")
      {:cancel, "eBay cookie needs attention"}
    else
      fetch(draft, job)
    end
  end

  # An unattended read is cancelled, not retried, while the cookie needs a person.
  defp blocked?(%Oban.Job{priority: @unattended}, %{photos: []}), do: Session.status() != :ok
  defp blocked?(_job, _draft), do: false

  defp fetch(draft, %Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
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
