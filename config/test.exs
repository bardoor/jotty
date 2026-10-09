import Config

suffix = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
database = Path.join(System.tmp_dir!(), "jotty-test-#{System.pid()}-#{suffix}.sqlite3")

config :jotty, Jotty.Repo, database: database, pool_size: 1
