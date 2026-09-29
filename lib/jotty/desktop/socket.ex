defmodule Jotty.Desktop.Socket do
  @moduledoc false

  @behaviour WebSock

  alias Jotty.Desktop.{Controller, Protocol}

  @impl WebSock
  def init(controller) do
    snapshot = Controller.attach(controller, self())
    {:push, {:text, Protocol.encode_event(snapshot)}, %{controller: controller}}
  end

  @impl WebSock
  def handle_in({payload, opcode: :text}, state) do
    run(Protocol.decode!(payload), state.controller)
    {:ok, state}
  end

  @impl WebSock
  def handle_info({:jotty_desktop_event, event}, state) do
    {:push, {:text, Protocol.encode_event(event)}, state}
  end

  defp run(:start, controller), do: :ok = Controller.start_recording(controller)
  defp run(:stop, controller), do: :ok = Controller.stop_recording(controller)
end
