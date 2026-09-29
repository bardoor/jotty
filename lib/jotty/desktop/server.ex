defmodule Jotty.Desktop.Server do
  @moduledoc false

  alias Jotty.Desktop.{Controller, Router}

  @enforce_keys [:controller, :listener, :port]
  defstruct @enforce_keys

  @type t :: %__MODULE__{controller: pid(), listener: pid(), port: :inet.port_number()}

  @spec start(keyword()) :: {:ok, t()} | {:error, term()}
  def start(options) do
    port = Keyword.fetch!(options, :port)
    {:ok, controller} = Controller.start_link(record: Keyword.fetch!(options, :record))

    case Bandit.start_link(
           plug: {Router, controller: controller},
           ip: :loopback,
           port: port,
           startup_log: false
         ) do
      {:ok, listener} ->
        {:ok, %__MODULE__{controller: controller, listener: listener, port: port}}

      {:error, reason} ->
        GenServer.stop(controller)
        {:error, reason}
    end
  end

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{} = server) do
    GenServer.stop(server.listener)
    GenServer.stop(server.controller)
  end
end
