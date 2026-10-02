defmodule Jotty.Desktop.Server do
  @moduledoc false

  alias Jotty.Desktop.Router
  alias Jotty.Session.Server, as: SessionServer

  @enforce_keys [:session, :listener, :port]
  defstruct @enforce_keys

  @type t :: %__MODULE__{session: pid(), listener: pid(), port: :inet.port_number()}

  @spec start(keyword()) :: {:ok, t()} | {:error, term()}
  def start(options) do
    port = Keyword.fetch!(options, :port)
    {:ok, session} = SessionServer.start_link(Keyword.fetch!(options, :session_options))
    opts = [plug: {Router, session: session}, ip: :loopback, port: port, startup_log: false]

    case Bandit.start_link(opts) do
      {:ok, listener} ->
        {:ok, %__MODULE__{session: session, listener: listener, port: port}}

      {:error, reason} ->
        GenServer.stop(session)
        {:error, reason}
    end
  end

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{} = server) do
    GenServer.stop(server.listener)
    GenServer.stop(server.session)
  end
end
