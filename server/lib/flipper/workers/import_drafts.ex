defmodule Flipper.Workers.ImportDrafts do
  @moduledoc """
  Imports the Seller Hub drafts list, hourly and as a server starts.
  """

  use Oban.Worker, queue: :ebay_automated, max_attempts: 1

  alias Flipper.Drafts
  alias Flipper.Ebay.Session

  require Logger

  @impl true
  def perform(_job), do: run()

  def run do
    case Session.status() do
      :ok -> import_drafts()
      _status -> {:cancel, "eBay cookie needs attention"}
    end
  end

  defp import_drafts do
    with {:error, reason} <- Drafts.import_from_ebay() do
      Logger.warning("eBay drafts import failed: #{reason}")
      {:error, reason}
    end
  end
end
