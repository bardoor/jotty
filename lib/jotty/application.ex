defmodule Jotty.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _arguments) do
    options = [strategy: :one_for_one, name: Jotty.Supervisor]
    Supervisor.start_link([Jotty.Repo], options)
  end
end
