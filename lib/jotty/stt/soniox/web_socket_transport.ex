defmodule Jotty.STT.Soniox.WebSocketTransport do
  @moduledoc false

  @behaviour Jotty.STT.Soniox.Transport
  use WebSockex
  require Logger

  @impl Jotty.STT.Soniox.Transport
  def start(owner, :mixed, configuration, []) do
    state = %{
      owner: owner,
      configuration: configuration,
      logger_metadata: Logger.metadata()
    }

    WebSockex.start(
      "wss://stt-rt.soniox.com/transcribe-websocket",
      __MODULE__,
      state,
      insecure: false,
      cacerts: :public_key.cacerts_get(),
      socket_options: [send_timeout: 5_000, send_timeout_close: true]
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
    Process.send_after(self(), :ping, 5_000)
    {:ok, Map.put(state, :pong_timer, nil)}
  end

  @impl WebSockex
  def handle_info(:send_configuration, state) do
    {:reply, {:text, state.configuration}, state}
  end

  def handle_info(:ping, state) do
    timer = :erlang.start_timer(10_000, self(), :pong)
    {:reply, {:ping, "jotty"}, %{state | pong_timer: timer}}
  end

  def handle_info({:timeout, timer, :pong}, %{pong_timer: timer} = state), do: {:close, state}
  def handle_info({:timeout, _timer, :pong}, state), do: {:ok, state}

  @impl WebSockex
  def handle_pong({:pong, "jotty"}, %{pong_timer: timer} = state) when is_reference(timer) do
    Process.cancel_timer(timer)
    Process.send_after(self(), :ping, 5_000)
    {:ok, %{state | pong_timer: nil}}
  end

  def handle_pong(_frame, state), do: {:ok, state}

  @impl WebSockex
  def handle_frame({:text, payload}, state) do
    send(state.owner, {:soniox_transport, self(), {:text, payload}})
    {:ok, state}
  end

  def handle_frame({:binary, _payload}, state) do
    send(state.owner, {:soniox_transport, self(), {:unexpected_frame, :binary}})
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast(:stop, state), do: {:close, state}

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.info("transport_disconnected", scope: :transcription, provider: :soniox, reason: inspect(reason))
    send(state.owner, {:soniox_transport, self(), disconnect(reason)})
    {:ok, state}
  end

  defp disconnect({:remote, :normal}), do: :closed
  defp disconnect({:remote, 1000, _message}), do: :closed
  defp disconnect(_reason), do: {:error, :disconnected}
end
