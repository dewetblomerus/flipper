defmodule Flipper.Workers.ImportDrafts do
  @moduledoc """
  Imports the Seller Hub drafts list: hourly, as a server starts, and when a person asks.
  One import job waits or runs at a time.
  """

  alias Flipper.Workers.EbayPriority

  use Oban.Worker,
    queue: :ebay_cookie_requests,
    priority: EbayPriority.unattended_read(),
    max_attempts: 1,
    unique: [period: :infinity, states: :incomplete, fields: [:worker]]

  alias Flipper.Drafts
  alias Flipper.Ebay.Session

  require Logger

  @impl true
  def perform(_job) do
    result =
      case Session.status() do
        :ok -> import_drafts()
        _status -> {:cancel, "eBay cookie needs attention"}
      end

    Drafts.broadcast_import(result)
    result
  end

  defp import_drafts do
    with {:error, reason} <- Drafts.import_from_ebay() do
      Logger.warning("eBay drafts import failed: #{reason}")
      {:error, reason}
    end
  end
end
