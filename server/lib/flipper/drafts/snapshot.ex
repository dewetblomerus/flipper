defmodule Flipper.Drafts.Snapshot do
  @moduledoc """
  The eBay draft as first read after photo approval. It is never overwritten.
  """

  use Ecto.Schema

  schema "draft_snapshots" do
    belongs_to :draft, Flipper.Drafts.Draft
    field :modules, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
