import Config

# Each checkout tests against its own database, so one branch's migrations can't break
# another's tests. A checkout named flipper-my-branch uses flipper_test_my_branch.
checkout =
  Path.expand("../..", __DIR__)
  |> Path.basename()
  |> String.replace_prefix("flipper", "")
  |> String.replace(~r/[^a-z0-9]+/i, "_")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :flipper, Flipper.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "flipper_test#{checkout}#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :flipper, FlipperWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BEwqx1m02D5GdH1PRHO+AgXEpipJ3IAJr4K246SP6TFUqmB23V0/3WEjcjhnc8/R",
  server: false

# In test we don't send emails
config :flipper, Flipper.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

config :flipper, Oban, testing: :manual, queues: false, plugins: false

config :flipper,
  photo_dir: Path.expand("../tmp/test_uploads", __DIR__),
  ebay_cookie_path: Path.expand("../tmp/ebay_cookie", __DIR__),
  photo_editor: Flipper.Photos.FakeEditor,
  seller_hub: Flipper.Ebay.FakeSellerHub

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
