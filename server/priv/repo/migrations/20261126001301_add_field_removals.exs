defmodule Flipper.Repo.Migrations.AddFieldRemovals do
  use Ecto.Migration

  def change do
    alter table(:drafts) do
      add :approved_removals, {:array, :text}
      add :removal_error, :text
    end

    create table(:draft_snapshots, primary_key: false) do
      add :id, :identity, primary_key: true
      add :draft_id, references(:drafts, on_delete: :delete_all), null: false
      add :modules, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:draft_snapshots, [:draft_id])
  end
end
