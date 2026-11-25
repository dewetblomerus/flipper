defmodule Flipper.Repo.Migrations.MoveDraftsJobsToEbayQueue do
  use Ecto.Migration

  def up do
    execute """
    UPDATE oban_jobs SET queue = 'ebay'
    WHERE queue = 'drafts' AND state IN ('available', 'scheduled', 'retryable')
    """
  end

  def down, do: :ok
end
