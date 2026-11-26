defmodule Flipper.Workers.RecordLostEbayWrites do
  @moduledoc """
  Records an error on each approved eBay write with no job left to run it, so a person can
  retry it. This covers a job that ends before its worker records an error.
  """

  # The next minute's run is the retry.
  use Oban.Worker, queue: :upkeep, max_attempts: 1

  alias Flipper.Drafts

  @impl true
  def perform(_job), do: Drafts.record_lost_ebay_writes()
end
