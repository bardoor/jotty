defmodule Jotty.STT.Soniox.WebSocketTransport do
  @moduledoc false

  @behaviour Jotty.STT.Soniox.Transport
  use WebSockex
  require Logger

  @impl Jotty.STT.Soniox.Transport
  def start(owner, source, configuration, []) do
    state = %{
      owner: owner,
      source: source,
      configuration: configuration,
      logger_metadata: Logger.metadata()
    }

    WebSockex.start(
      "wss://stt-rt.soniox.com/transcribe-websocket",
      __MODULE__,
      state,
      insecure: false,
      cacerts: :public_key.cacerts_get()
    )
  end

  @impl Jotty.STT.Soniox.Transport
  def send_binary(pid, binary) do
    try do
      WebSockex.send_frame(pid, {:binary, binary})
    catch
      :exit, _reason -> {:error, :not_connected}
    end
  end

  @impl Jotty.STT.Soniox.Transport
  def finish(pid) do
    try do
      WebSockex.send_frame(pid, {:text, ""})
    catch
      :exit, _reason -> {:error, :not_connected}
    end
  end

  @impl Jotty.STT.Soniox.Transport
  def stop(pid) do
    WebSockex.cast(pid, :stop)
  end

  @impl WebSockex
  def handle_connect(_connection, state) do
    Logger.metadata(state.logger_metadata)
    send(self(), :send_configuration)
    {:ok, Map.delete(state, :logger_metadata)}
  end

  @impl WebSockex
  def handle_info(:send_configuration, state) do
    {:reply, {:text, state.configuration}, state}
  end

  @impl WebSockex
  def handle_frame({:text, payload}, state) do
    send(state.owner, {:soniox_transport, state.source, {:text, payload}})
    {:ok, state}
  end

  def handle_frame({:binary, _payload}, state) do
    send(state.owner, {:soniox_transport, state.source, {:unexpected_frame, :binary}})
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast(:stop, state), do: {:close, state}

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.info("transport_disconnected", scope: :transcription, provider: :soniox, reason: inspect(reason))
    send(state.owner, {:soniox_transport, state.source, disconnect(reason)})
    {:ok, state}
  end

  defp disconnect({:remote, :normal}), do: :closed
  defp disconnect({:remote, 1000, _message}), do: :closed
  defp disconnect(_reason), do: {:error, :disconnected}
end
