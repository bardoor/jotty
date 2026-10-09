defmodule Jotty.Desktop.Server do
  @moduledoc false

  alias Jotty.Desktop.{Controller, Router}

  @type t :: %__MODULE__{controller: pid(), listener: pid(), port: :inet.port_number()}

  @enforce_keys ~w(controller listener port)a
  defstruct ~w(controller listener port)a

  @spec start(keyword()) :: {:ok, t()} | {:error, term()}
  def start(options) do
    port = Keyword.fetch!(options, :port)
    session_options = Keyword.fetch!(options, :session_options)
    recorder = Keyword.fetch!(session_options, :recorder)

    controller_options = [
      home: Keyword.get(options, :home, System.user_home!()),
      recorder: recorder,
      session_options: Keyword.delete(session_options, :recording),
      audio_base_url: "http://127.0.0.1:#{port}"
    ]

    {:ok, controller} = Controller.start_link(controller_options)

    socket_context = %{
      controller: controller,
      recorder: recorder,
      context_approval_secret: Keyword.get(options, :context_approval_secret)
    }

    opts = [
      plug: {Router, controller: controller, socket_context: socket_context},
      ip: :loopback,
      port: port,
      startup_log: false
    ]

    case Bandit.start_link(opts) do
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
