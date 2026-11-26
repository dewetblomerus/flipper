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
    field :use_edited, :boolean
    field :edited_ebay_url, :string
    field :replaced_on_ebay_at, :utc_datetime_usec
    field :ebay_error, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:draft_id, :position, :original_path, :original_content_type])
    |> validate_required([:draft_id, :position, :original_path, :original_content_type])
    |> unique_constraint([:draft_id, :position])
  end

  def edit_changeset(photo, attrs) do
    photo
    |> cast(attrs, [
      :edited_path,
      :edited_content_type,
      :subject_left,
      :subject_top,
      :subject_width,
      :subject_height
    ])
    |> validate_required([
      :edited_path,
      :edited_content_type,
      :subject_left,
      :subject_top,
      :subject_width,
      :subject_height
    ])
    |> validate_number(:subject_left, greater_than_or_equal_to: 0)
    |> validate_number(:subject_top, greater_than_or_equal_to: 0)
    |> validate_number(:subject_width, greater_than: 0)
    |> validate_number(:subject_height, greater_than: 0)
    |> check_constraint(:subject_left, name: :photos_subject_box)
  end
end
