defmodule Jotty.Desktop.SocketTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Jotty.Desktop.Socket
  alias Jotty.Recording
  alias Jotty.Session.Server

  @tag :tmp_dir
  test "sends the current snapshot and forwards presentation events", %{tmp_dir: directory} do
    recording = %Recording{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }

    {:ok, session} =
      Server.start_link(api_key: "test-key", recorder: "/unused", recording: recording)

    assert {:push, {:text, snapshot}, %{session: ^session} = state} = Socket.init(session)
    assert %{"type" => "snapshot", "status" => "idle"} = Jason.decode!(snapshot)

    event = %{type: :state, status: :starting}

    assert {:push, {:text, encoded_event}, ^state} =
             Socket.handle_info({:jotty_desktop_event, event}, state)

    assert Jason.decode!(encoded_event) == %{"type" => "state", "status" => "starting"}
    GenServer.stop(session)
  end

  @tag :tmp_dir
  test "logs the desktop connection with the session correlation", %{tmp_dir: directory} do
    recording = %Recording{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }

    {:ok, session} = Server.start_link(api_key: "test-key", recorder: "/unused", recording: recording)

    log =
      capture_log([metadata: [:scope, :session_id, :reason]], fn ->
        assert {:push, {:text, _snapshot}, state} = Socket.init(session)
        assert :ok = Socket.terminate(:closed, state)
        Logger.flush()
      end)

    assert log =~ "connected"
    assert log =~ "disconnected"
    assert log =~ "scope=desktop"
    assert log =~ "session_id=#{inspect(session)}"
    assert log =~ "reason=:closed"
    GenServer.stop(session)
  end
end
