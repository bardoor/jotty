defmodule Jotty.Desktop.ServerTest do
  use ExUnit.Case, async: true

  alias Jotty.Desktop.Server
  alias Jotty.Recorder

  defmodule Client do
    use WebSockex

    def start(url, test_pid), do: WebSockex.start_link(url, __MODULE__, test_pid)

    @impl WebSockex
    def handle_frame({:text, payload}, test_pid) do
      send(test_pid, {:desktop_frame, Jason.decode!(payload)})
      {:ok, test_pid}
    end

    @impl WebSockex
    def handle_cast(:close, test_pid), do: {:close, test_pid}
  end

  test "serves health on the configured loopback port" do
    port = free_port()
    record = fn _event_sink -> {:error, :unused} end

    assert {:ok, server} = Server.start(record: record, port: port)
    assert %{status: 200, body: "ok"} = Req.get!("http://127.0.0.1:#{port}/health")
    assert :ok = Server.stop(server)
  end

  test "upgrades a WebSocket and carries recording commands and events" do
    port = free_port()

    record = fn event_sink ->
      send(event_sink, {:jotty_session_event, :recording_started})
      receive do: (:stop -> {:error, :stopped})
    end

    assert {:ok, server} = Server.start(record: record, port: port)
    assert {:ok, client} = Client.start("ws://127.0.0.1:#{port}/ws", self())

    assert_receive {:desktop_frame, %{"type" => "snapshot", "status" => "idle"}}

    :ok = WebSockex.send_frame(client, {:text, ~s({"type":"start"})})
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "starting"}}
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "recording"}}

    :ok = WebSockex.send_frame(client, {:text, ~s({"type":"stop"})})
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "stopping"}}

    WebSockex.cast(client, :close)
    assert :ok = Server.stop(server)
  end

  @tag :tmp_dir
  test "stops the native recorder through the WebSocket command", %{tmp_dir: directory} do
    port = free_port()
    executable = fake_live_recorder!(directory)
    test_pid = self()

    record = fn event_sink ->
      result =
        Recorder.record_live(
          executable,
          directory,
          fn
            :ready -> send(event_sink, {:jotty_session_event, :recording_started})
            _event -> :ok
          end,
          stop: :message
        )

      send(test_pid, {:record_result, result})
      {:error, :test_complete}
    end

    assert {:ok, server} = Server.start(record: record, port: port)
    assert {:ok, client} = Client.start("ws://127.0.0.1:#{port}/ws", self())
    assert_receive {:desktop_frame, %{"type" => "snapshot", "status" => "idle"}}

    :ok = WebSockex.send_frame(client, {:text, ~s({"type":"start"})})
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "starting"}}
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "recording"}}, 1_000

    :ok = WebSockex.send_frame(client, {:text, ~s({"type":"stop"})})
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "stopping"}}
    assert_receive {:record_result, :ok}, 1_000
    assert File.exists?(Path.join(directory, "stopped"))

    WebSockex.cast(client, :close)
    assert :ok = Server.stop(server)
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, active: false)
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp fake_live_recorder!(directory) do
    executable = Path.join(directory, "live-recorder")

    File.write!(executable, """
    #!/usr/bin/python3
    import pathlib
    import signal
    import struct
    import sys
    import time

    output = pathlib.Path(sys.argv[-1])

    def stop(_signal, _frame):
        (output / "stopped").touch()
        raise SystemExit(0)

    signal.signal(signal.SIGINT, stop)
    payload = bytes([1])
    sys.stdout.buffer.write(struct.pack(">I", len(payload)) + payload)
    sys.stdout.buffer.flush()

    while True:
        time.sleep(1)
    """)

    File.chmod!(executable, 0o755)
    executable
  end
end
