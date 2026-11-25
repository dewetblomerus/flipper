defmodule Flipper.Drafts.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    belongs_to :draft, Flipper.Drafts.Draft
    field :position, :integer
    field :original_path, :string
    field :original_content_type, :string
    field :edited_path, :string
    field :edited_content_type, :string
    field :subject_left, :integer
    field :subject_top, :integer
    field :subject_width, :integer
    field :subject_height, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:draft_id, :position, :original_path, :original_content_type])
    |> validate_required([:draft_id, :position, :original_path, :original_content_type])
    |> unique_constraint([:draft_id, :position])
  end
end
