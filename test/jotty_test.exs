defmodule JottyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jotty.Recording
  alias Jotty.Session.Events.UtteranceCompleted

  @tag :tmp_dir
  test "records, transcribes one realtime mix, and summarizes one call", %{tmp_dir: home} do
    recorder = fake_live_recorder!(home)
    fake_codex!(home)

    result =
      capture_io("\n", fn ->
        send(
          self(),
          {:result,
           Jotty.record(home, recorder, "soniox-key", ~U[2026-09-21 17:45:00Z],
             session_options: [
               transport: Jotty.FakeSonioxTransport,
               transport_options: [test_pid: self(), auto_transcribe: true],
               shutdown_timeout: 1_000
             ]
           )}
        )
      end)

    assert result =~ "Press Enter to stop recording"
    assert_receive {:result, {:ok, %Recording{} = recording}}
    assert File.exists?(recording.system_audio)
    assert File.exists?(recording.microphone_audio)
    refute File.exists?(Path.join(recording.directory, "audio.m4a"))
    assert File.read!(recording.transcript) == "Speaker 1: What does the project use?"
    assert File.read!(recording.summary) == "# Summary\nRelease approved.\n"
  end

  @tag :tmp_dir
  test "records with live context assistance while preserving post-processing", %{tmp_dir: home} do
    recorder = fake_live_recorder!(home)
    context_directory = Path.join(home, "project")
    File.mkdir_p!(context_directory)
    fake_codex!(home)

    result =
      capture_io("\n", fn ->
        send(
          self(),
          {:result,
           Jotty.record(home, recorder, "soniox-key", ~U[2026-09-21 18:00:00Z],
             contexts: [context_directory],
             session_options: [
               transport: Jotty.FakeSonioxTransport,
               transport_options: [test_pid: self(), auto_transcribe: true],
               shutdown_timeout: 1_000
             ]
           )}
        )
      end)

    assert result =~ "Press Enter to stop recording"
    assert_receive {:result, {:ok, %Recording{} = recording}}
    assert File.exists?(recording.system_audio)
    assert File.exists?(recording.microphone_audio)
    refute File.exists?(Path.join(recording.directory, "audio.m4a"))
    assert File.read!(recording.transcript) == "Speaker 1: What does the project use?"
    assert File.read!(recording.summary) == "# Summary\nRelease approved.\n"

    assistant = File.read!(Path.join(recording.directory, "assistant.md"))
    assert assistant =~ "## Find project facts"
    assert assistant =~ "What does the project use?"
  end

  @tag :tmp_dir
  test "records with realtime transcription without project context", %{tmp_dir: home} do
    recorder = fake_live_recorder!(home)
    fake_codex!(home)
    receiver = self()

    task =
      Task.async(fn ->
        Jotty.record(home, recorder, "soniox-key", ~U[2026-09-21 19:00:00Z],
          recorder_stop: :message,
          event_sink: receiver,
          session_options: [
            transport: Jotty.FakeSonioxTransport,
            transport_options: [test_pid: receiver, auto_transcribe: true],
            shutdown_timeout: 1_000
          ]
        )
      end)

    on_exit(fn ->
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    assert_receive {:jotty_session_event, %UtteranceCompleted{}}, 1_000
    send(task.pid, :stop)

    assert {:ok, %Recording{} = recording} = Task.await(task, 5_000)
    assert File.read!(recording.transcript) == "Speaker 1: What does the project use?"
    assert File.read!(recording.summary) == "# Summary\nRelease approved.\n"
    refute File.exists?(Path.join(recording.directory, "assistant.md"))
  end

  defp fake_live_recorder!(home) do
    path = Path.join(home, "live-recorder")

    File.write!(path, """
    #!/usr/bin/python3
    import pathlib
    import signal
    import struct
    import subprocess
    import sys
    import time

    output = pathlib.Path(sys.argv[-1])

    def packet(payload):
        sys.stdout.buffer.write(struct.pack(">I", len(payload)) + payload)
        sys.stdout.buffer.flush()

    def stop(_signal, _frame):
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.1", "-c:a", "aac", str(output / "system.m4a")], check=True)
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=880:duration=0.1", "-c:a", "aac", str(output / "microphone.m4a")], check=True)
        raise SystemExit(0)

    signal.signal(signal.SIGINT, stop)
    packet(bytes([1]))
    packet(bytes([2, 1, 2]))

    while True:
        time.sleep(1)
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp fake_codex!(home) do
    bin_directory = Path.join(home, "bin")
    path = Path.join(bin_directory, "codex")
    File.mkdir!(bin_directory)

    File.write!(path, """
    #!/bin/sh
    output=""
    schema=0
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output-last-message" ]; then
        shift
        output="$1"
      elif [ "$1" = "--output-schema" ]; then
        schema=1
      fi
      shift
    done
    /bin/cat >/dev/null
    if [ "$schema" = "1" ]; then
      /usr/bin/printf '%s' '{"decision":{"action":"search","query":"Find project facts"}}' > "$output"
    else
      /usr/bin/printf '# Summary\nRelease approved.\n' > "$output"
    fi
    """)

    File.chmod!(path, 0o755)

    hermes = Path.join(bin_directory, "hermes")

    File.write!(hermes, """
    #!/bin/sh
    /usr/bin/printf 'Project facts.\n'
    """)

    File.chmod!(hermes, 0o755)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    on_exit(fn -> System.put_env("PATH", original_path) end)
  end
end
