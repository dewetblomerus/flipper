defmodule Flipper.Repo.Migrations.MoveEbayJobsToEbayCookieRequests do
  use Ecto.Migration

  # An orphaned executing job is rescued into its queue, so it moves too.
  def up do
    execute """
    UPDATE oban_jobs
    SET queue = 'ebay_cookie_requests',
        priority = CASE
          WHEN worker = 'Flipper.Workers.UpdateEbayDraft' THEN 0
          WHEN queue = 'ebay' THEN 1
          ELSE 2
        END
    WHERE queue IN ('ebay', 'ebay_automated')
      AND state IN ('available', 'scheduled', 'retryable', 'executing')
    """
  end

  def down, do: :ok
end
