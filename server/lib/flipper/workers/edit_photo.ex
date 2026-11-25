defmodule Flipper.Workers.EditPhoto do
  @moduledoc """
  Crops one photo and moves the draft when every photo is edited.
  """

  use Oban.Worker,
    queue: :photos,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: :incomplete,
      keys: [:photo_id]
    ]

  alias Flipper.Drafts

  @impl true
  def timeout(_job), do: :timer.minutes(5)

  @impl true
  def perform(%Oban.Job{args: %{"photo_id" => id}}) do
    Drafts.edit_photo(Drafts.get_photo!(id))
  end
end
