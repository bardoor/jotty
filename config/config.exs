import Config

config :jotty,
  soniox_poll_interval: 1_000,
  soniox_timeout: 3_600_000,
  soniox_req_options: []

import_config "#{config_env()}.exs"
