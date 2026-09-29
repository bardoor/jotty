defmodule Jotty.Desktop.SocketTest do
  use ExUnit.Case, async: true

  alias Jotty.Desktop.{Controller, Socket}

  test "sends the current snapshot and routes commands and events" do
    record = fn _event_sink ->
      receive do: (:stop -> {:error, :stopped})
    end

    {:ok, controller} = Controller.start_link(record: record)

    assert {:push, {:text, snapshot}, %{controller: ^controller} = state} = Socket.init(controller)
    assert %{"type" => "snapshot", "status" => "idle"} = Jason.decode!(snapshot)

    assert {:ok, ^state} = Socket.handle_in({~s({"type":"start"}), opcode: :text}, state)
    assert_receive {:jotty_desktop_event, %{type: :state, status: :starting} = event}

    assert {:push, {:text, encoded_event}, ^state} =
             Socket.handle_info({:jotty_desktop_event, event}, state)

    assert Jason.decode!(encoded_event) == %{"type" => "state", "status" => "starting"}

    send(controller, {:jotty_session_event, :recording_started})
    assert_receive {:jotty_desktop_event, %{type: :state, status: :recording}}

    assert {:ok, ^state} = Socket.handle_in({~s({"type":"stop"}), opcode: :text}, state)
  end
end
