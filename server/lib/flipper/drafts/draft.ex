defmodule Flipper.Drafts.Draft do
  use Ecto.Schema
  import Ecto.Changeset

  schema "drafts" do
    field :ebay_draft_id, :string
    field :title, :string
    field :state, :string
    field :fetch_error, :string
    has_many :photos, Flipper.Drafts.Photo

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(draft, ebay_draft_id) do
    draft
    |> change(ebay_draft_id: ebay_draft_id, state: "started")
    |> validate_required([:ebay_draft_id, :state])
    |> unique_constraint(:ebay_draft_id)
  end
end
