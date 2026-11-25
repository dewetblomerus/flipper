defmodule Flipper.Workers.ReplaceEbayPhoto do
  @moduledoc """
  Uploads the approved edit and makes it the draft's first photo on eBay.
  """

  use Oban.Worker,
    queue: :ebay,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: :incomplete,
      keys: [:photo_id]
    ]

  alias Flipper.Drafts

  @impl true
  def perform(%Oban.Job{args: %{"photo_id" => id}, attempt: attempt, max_attempts: max_attempts}) do
    photo = Drafts.get_photo!(id)

    case Drafts.replace_on_ebay(photo) do
      :ok ->
        :ok

      {:error, reason} when attempt == max_attempts ->
        Drafts.record_ebay_error(Drafts.get_photo!(id), error_message(reason))
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
