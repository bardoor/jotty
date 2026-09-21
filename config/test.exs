import Config

config :jotty,
  soniox_poll_interval: 0,
  soniox_req_options: [plug: {Req.Test, Jotty.Soniox}]
