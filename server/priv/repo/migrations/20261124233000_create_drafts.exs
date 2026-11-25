defmodule Flipper.Repo.Migrations.CreateDrafts do
  use Ecto.Migration

  def change do
    create table(:drafts, primary_key: false) do
      add :id, :identity, primary_key: true
      add :ebay_draft_id, :text, null: false
      add :title, :text
      add :state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:drafts, [:ebay_draft_id])
  end
end
