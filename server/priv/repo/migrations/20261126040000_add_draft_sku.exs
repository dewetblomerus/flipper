defmodule Flipper.Repo.Migrations.AddDraftSku do
  use Ecto.Migration

  def change do
    alter table(:drafts) do
      add :sku, :text
      add :import_read_at, :utc_datetime_usec
    end

    execute "UPDATE drafts SET state = 'awaiting_sku' WHERE state = 'awaiting_photos'",
            "UPDATE drafts SET state = 'awaiting_photos' WHERE state = 'awaiting_sku'"
  end
end
