defmodule Flipper.Repo.Migrations.AddDraftListedAt do
  use Ecto.Migration

  def change do
    alter table(:drafts) do
      add :listed_at, :utc_datetime_usec
    end
  end
end
