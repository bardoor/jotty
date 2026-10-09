[
  line_length: 112,
  import_deps: ~w(ecto ecto_sql)a,
  locals_without_parens: [
    field: 1,
    field: 2,
    field: 3,
    belongs_to: 2,
    belongs_to: 3,
    has_one: 2,
    has_one: 3,
    has_many: 2,
    has_many: 3,
    many_to_many: 2,
    many_to_many: 3
  ],
  inputs: [
    "{mix,.formatter}.exs",
    "config/{config,dev,prod,test}.exs",
    "priv/repo/migrations/*.exs",
    "{lib,test}/**/*.{ex,exs}"
  ]
]
