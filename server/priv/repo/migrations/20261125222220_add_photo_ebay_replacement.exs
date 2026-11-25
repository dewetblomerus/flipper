defmodule Flipper.Repo.Migrations.AddPhotoEbayReplacement do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :edited_ebay_url, :string
      add :replaced_on_ebay_at, :utc_datetime_usec
      add :ebay_error, :string
    end
  end
end
