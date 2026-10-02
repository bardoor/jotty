defmodule Jotty.Desktop.Socket do
  @moduledoc false

  @behaviour WebSock

  require Logger

  alias Jotty.Desktop.Protocol
  alias Jotty.Session.Server

  @impl WebSock
  def init(session) do
    Logger.metadata(session_id: inspect(session))
    Logger.info("connected", scope: :desktop)
    snapshot = Server.attach(session, self())
    {:push, {:text, Protocol.encode_event(snapshot)}, %{session: session}}
  end

  @impl WebSock
  def handle_in({payload, opcode: :text}, state) do
    run(Protocol.decode!(payload), state.session)
    {:ok, state}
  end

  @impl WebSock
  def handle_info({:jotty_desktop_event, event}, state) do
    {:push, {:text, Protocol.encode_event(event)}, state}
  end

  @impl WebSock
  def terminate(reason, _state) do
    Logger.info("disconnected", scope: :desktop, reason: inspect(reason))
  end

  defp run(:start, session) do
    Logger.info("start_requested", scope: :desktop)
    :ok = Server.start_recording(session)
  end

  defp run(:stop, session) do
    Logger.info("stop_requested", scope: :desktop)
    :ok = Server.stop_recording(session)
  end
end
