defmodule Flipper.Repo.Migrations.RemovePhotoSubjectAngle do
  use Ecto.Migration

  def up do
    drop constraint(:photos, :photos_subject_box)

    alter table(:photos) do
      remove :subject_angle
    end

    create constraint(:photos, :photos_subject_box,
             check: """
             (subject_left IS NULL AND subject_top IS NULL AND subject_width IS NULL AND subject_height IS NULL)
             OR
             (subject_left IS NOT NULL AND subject_top IS NOT NULL
              AND subject_width IS NOT NULL AND subject_height IS NOT NULL
              AND subject_width > 0 AND subject_height > 0)
             """
           )
  end

  def down do
    drop constraint(:photos, :photos_subject_box)

    alter table(:photos) do
      add :subject_angle, :float
    end

    execute "UPDATE photos SET subject_angle = 0 WHERE subject_left IS NOT NULL"

    create constraint(:photos, :photos_subject_box,
             check: """
             (subject_left IS NULL AND subject_top IS NULL AND subject_width IS NULL AND subject_height IS NULL AND subject_angle IS NULL)
             OR
             (subject_left IS NOT NULL AND subject_top IS NOT NULL
              AND subject_width IS NOT NULL AND subject_height IS NOT NULL
              AND subject_width > 0 AND subject_height > 0 AND subject_angle IS NOT NULL)
             """
           )
  end
end
