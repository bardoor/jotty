defmodule Jotty.Repo do
  use Ecto.Repo,
    otp_app: :jotty,
    adapter: Ecto.Adapters.SQLite3

  @impl Ecto.Repo
  def init(_context, configuration) do
    database = Keyword.get(configuration, :database) || default_database()
    File.mkdir_p!(Path.dirname(database))
    {:ok, Keyword.put(configuration, :database, database)}
  end

  defp default_database, do: Path.join([System.user_home!(), ".jotty", "jotty.sqlite3"])
end
