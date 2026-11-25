defmodule Flipper.Repo.Migrations.AddPhotoEditChoice do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :use_edited, :boolean
    end

    create constraint(:photos, :photos_subject_box,
             check: """
             (subject_left IS NULL AND subject_top IS NULL AND subject_width IS NULL AND subject_height IS NULL)
             OR
             (subject_left IS NOT NULL AND subject_top IS NOT NULL AND subject_width > 0 AND subject_height > 0)
             """
           )
  end
end
