defmodule Jotty.Desktop.ServerTest do
  use ExUnit.Case, async: false

  alias Jotty.Desktop.Server
  alias Jotty.Recording

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

  defmodule FakeSummarizer do
    def summarize(_transcript, summary), do: File.write(summary, "# Summary\nDone.\n")
  end

  @tag :tmp_dir
  test "serves health on the configured loopback port", %{tmp_dir: directory} do
    port = free_port()

    assert {:ok, server} =
             Server.start(port: port, session_options: session_options(directory, "/unused"))

    assert %{status: 200, body: "ok"} = Req.get!("http://127.0.0.1:#{port}/health")
    assert :ok = Server.stop(server)
  end

  @tag :tmp_dir
  test "carries typed start and stop through the WebSocket to the native recorder", %{tmp_dir: directory} do
    port = free_port()
    executable = fake_live_recorder!(directory)

    assert {:ok, server} =
             Server.start(port: port, session_options: session_options(directory, executable))

    assert {:ok, client} = Client.start("ws://127.0.0.1:#{port}/ws", self())
    assert_receive {:desktop_frame, %{"type" => "snapshot", "status" => "idle"}}

    :ok = WebSockex.send_frame(client, {:text, ~s({"type":"start"})})
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "starting"}}
    assert_receive {:transport_started, transport, _owner, :mixed, _configuration}
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "recording"}}, 2_000

    :ok = WebSockex.send_frame(client, {:text, ~s({"type":"stop"})})
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "stopping"}}
    assert_receive {:transport_finished, ^transport, :mixed}, 2_000
    assert File.exists?(Path.join(directory, "stopped"))

    send(transport, {:text, ~s({"finished":true})})

    assert_receive {:desktop_frame,
                    %{
                      "type" => "summary_ready",
                      "markdown" => "# Summary\nDone.\n",
                      "recording_directory" => ^directory
                    }},
                   2_000

    WebSockex.cast(client, :close)
    assert :ok = Server.stop(server)
  end

  @tag :tmp_dir
  test "stops session-owned processes when the desktop server stops", %{tmp_dir: directory} do
    port = free_port()
    executable = fake_live_recorder!(directory)

    assert {:ok, server} =
             Server.start(port: port, session_options: session_options(directory, executable))

    assert {:ok, client} = Client.start("ws://127.0.0.1:#{port}/ws", self())
    assert_receive {:desktop_frame, %{"type" => "snapshot", "status" => "idle"}}

    :ok = WebSockex.send_frame(client, {:text, ~s({"type":"start"})})
    assert_receive {:transport_started, transport, _owner, :mixed, _configuration}
    assert_receive {:desktop_frame, %{"type" => "state", "status" => "recording"}}, 2_000

    assert :ok = Server.stop(server)
    assert_receive {:transport_stopped, ^transport, :mixed}, 2_000
    assert_eventually(fn -> File.exists?(Path.join(directory, "stopped")) end)
  end

  defp session_options(directory, executable) do
    recording = %Recording{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }

    [
      api_key: "test-key",
      recorder: executable,
      recorder_options: [stop: :message],
      recording: recording,
      summarizer: FakeSummarizer,
      transport: Jotty.FakeSonioxTransport,
      transport_options: [test_pid: self()]
    ]
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, active: false)
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp assert_eventually(assertion, attempts \\ 100)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")

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
        (output / "system.m4a").touch()
        (output / "microphone.m4a").touch()
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
