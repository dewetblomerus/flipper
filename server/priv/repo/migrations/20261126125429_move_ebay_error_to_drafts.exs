defmodule Flipper.Repo.Migrations.MoveEbayErrorToDrafts do
  use Ecto.Migration

  def change do
    rename table(:drafts), :removal_error, to: :ebay_error

    alter table(:photos) do
      remove :ebay_error, :string
    end
  end
end
