defmodule Flipper.Drafts.Draft do
  use Ecto.Schema
  import Ecto.Changeset

  # Every state, the least far along first.
  @states ~w(started awaiting_sku photos_taken photo_edits_drafted photo_edits_approved
             field_removals_drafted field_removals_approved finished)

  schema "drafts" do
    field :ebay_draft_id, :string
    field :title, :string
    field :sku, :string
    field :state, :string
    field :fetch_error, :string
    field :import_read_at, :utc_datetime_usec
    field :listed_at, :utc_datetime_usec
    field :approved_removals, {:array, :string}
    field :removal_error, :string
    has_many :photos, Flipper.Drafts.Photo

    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states

  def create_changeset(draft, ebay_draft_id) do
    draft
    |> change(ebay_draft_id: ebay_draft_id, state: "started")
    |> validate_required([:ebay_draft_id, :state])
    |> unique_constraint(:ebay_draft_id)
  end
end
