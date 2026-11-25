defmodule Flipper.Repo do
  use Ecto.Repo,
    otp_app: :flipper,
    adapter: Ecto.Adapters.Postgres
end
