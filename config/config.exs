import Config

config :jotty, ecto_repos: [Jotty.Repo]

config :jotty, Jotty.Repo,
  database: nil,
  pool_size: 1

config :logger, :default_handler, formatter: {Jotty.LogFormatter, %{}}

import_config "#{config_env()}.exs"
