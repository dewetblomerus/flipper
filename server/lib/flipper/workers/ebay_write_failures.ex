defmodule Flipper.Workers.EbayWriteFailures do
  @moduledoc "Makes interrupted eBay writes retryable once Oban discards them."

  import Ecto.Query

  alias Flipper.Drafts
  alias Flipper.Drafts.{Draft, Photo}
  alias Flipper.Repo
  alias Flipper.Workers.{RemoveEbayFields, ReplaceEbayPhoto}

  @workers Enum.map([RemoveEbayFields, ReplaceEbayPhoto], &Oban.Worker.to_string/1)
  @interrupted "The final eBay attempt ended before it finished."

  def attach do
    case :telemetry.attach_many(
           __MODULE__,
           [[:oban, :job, :exception], [:oban, :plugin, :stop]],
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  # A normal error return already records the reason in the worker.
  def handle_event([:oban, :job, :exception], _, %{result: {:error, _}}, _), do: :ok

  def handle_event([:oban, :job, :exception], _, %{state: :discard, job: job}, _) do
    record_failure(job)
  end

  def handle_event(
        [:oban, :plugin, :stop],
        _,
        %{plugin: Oban.Lifeline, discarded_jobs: jobs},
        _
      ) do
    ids = for %{id: id, queue: "ebay"} <- jobs, do: id

    if ids != [] do
      from(job in Oban.Job, where: job.id in ^ids and job.worker in ^@workers)
      |> Repo.all()
      |> Enum.each(&record_failure/1)
    end
  end

  def handle_event(_, _, _, _), do: :ok

  defp record_failure(%Oban.Job{
         worker: "Flipper.Workers.ReplaceEbayPhoto",
         args: %{"photo_id" => id}
       }) do
    case Repo.get(Photo, id) do
      %Photo{ebay_error: nil, replaced_on_ebay_at: nil} = photo ->
        Drafts.record_ebay_error(photo, @interrupted)

      _photo ->
        :ok
    end
  end

  defp record_failure(%Oban.Job{
         worker: "Flipper.Workers.RemoveEbayFields",
         args: %{"draft_id" => id}
       }) do
    case Repo.get(Draft, id) do
      %Draft{state: "field_removals_approved", removal_error: nil} = draft ->
        Drafts.record_removal_error(draft, @interrupted)

      _draft ->
        :ok
    end
  end

  defp record_failure(_job), do: :ok
end
