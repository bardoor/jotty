defmodule Jotty.Desktop.SocketTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jotty.Desktop.{Controller, Socket}

  @tag :tmp_dir
  test "sends the controller snapshot and forwards presentation events", %{tmp_dir: directory} do
    {:ok, controller} = controller(directory)
    context = %{controller: controller, recorder: "/unused", context_approval_secret: nil}

    assert {:push, {:text, snapshot}, %{controller: ^controller} = state} = Socket.init(context)
    assert %{"type" => "snapshot", "status" => "idle"} = Jason.decode!(snapshot)

    event = %{type: :state, status: :starting}

    assert {:push, {:text, encoded_event}, ^state} =
             Socket.handle_info({:jotty_desktop_event, event}, state)

    assert Jason.decode!(encoded_event) == %{"type" => "state", "status" => "starting"}
    GenServer.stop(controller)
  end

  @tag :tmp_dir
  test "logs the desktop connection with controller correlation", %{tmp_dir: directory} do
    {:ok, controller} = controller(directory)

    log =
      capture_log([metadata: ~w(scope controller_id reason)a], fn ->
        assert {:push, {:text, _snapshot}, state} =
                 Socket.init(%{controller: controller, recorder: "/unused", context_approval_secret: nil})

        assert :ok = Socket.terminate(:closed, state)
        Logger.flush()
      end)

    assert log =~ "connected"
    assert log =~ "disconnected"
    assert log =~ "scope=desktop"
    assert log =~ "controller_id=#{inspect(controller)}"
    assert log =~ "reason=:closed"
    GenServer.stop(controller)
  end

  defp controller(home) do
    Controller.start_link(
      home: home,
      recorder: "/unused",
      session_options: [api_key: "test-key"],
      audio_base_url: "http://127.0.0.1:4765"
    )
  end
end
