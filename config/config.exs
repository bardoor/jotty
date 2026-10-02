import Config

config :logger, :default_handler, formatter: {Jotty.LogFormatter, %{}}

import_config "#{config_env()}.exs"
