defmodule Flipper.Repo.Migrations.AddPhotos do
  use Ecto.Migration

  def change do
    alter table(:drafts) do
      add :fetch_error, :text
    end

    create table(:photos, primary_key: false) do
      add :id, :identity, primary_key: true
      add :draft_id, references(:drafts, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :original_path, :text, null: false
      add :original_content_type, :text, null: false
      add :edited_path, :text
      add :edited_content_type, :text
      add :subject_left, :integer
      add :subject_top, :integer
      add :subject_width, :integer
      add :subject_height, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:photos, [:draft_id, :position])
  end
end
