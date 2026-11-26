defmodule Flipper.Drafts.Snapshot do
  @moduledoc """
  The first valid eBay draft read after photo approval.
  """

  use Ecto.Schema

  schema "draft_snapshots" do
    belongs_to :draft, Flipper.Drafts.Draft
    field :modules, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
