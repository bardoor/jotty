defmodule Jotty.RecorderTest do
  use ExUnit.Case, async: true

  alias Jotty.Recorder
  import ExUnit.CaptureIO

  @tag :tmp_dir
  test "waits for the native recorder to finalize both source tracks", %{tmp_dir: directory} do
    executable = Path.join(directory, "recorder")

    File.write!(executable, """
    #!/bin/sh
    /usr/bin/touch "$1/system.m4a"
    /usr/bin/touch "$1/microphone.m4a"
    exit 0
    """)

    File.chmod!(executable, 0o755)

    assert :ok = Recorder.record(executable, directory)
    assert File.exists?(Path.join(directory, "system.m4a"))
    assert File.exists?(Path.join(directory, "microphone.m4a"))
  end

  @tag :tmp_dir
  test "sends SIGINT to the native recorder after framed ready", %{tmp_dir: directory} do
    executable = Path.join(directory, "recorder")
    write_fake_recorder(executable, [<<1>>])

    capture_io("\n", fn ->
      assert :ok = Recorder.record(executable, directory)
    end)

    assert File.exists?(Path.join(directory, "system.m4a"))
    assert File.exists?(Path.join(directory, "microphone.m4a"))
  end

  @tag :tmp_dir
  test "opts into live output and routes each closed source packet", %{tmp_dir: directory} do
    executable = Path.join(directory, "recorder")
    write_fake_recorder(executable, [<<1>>, <<2, 1, 2>>, <<3, 3, 4>>, <<4, 2, 1>>])
    receiver = self()

    capture_io("\n", fn ->
      assert :ok = Recorder.record_live(executable, directory, &send(receiver, {:live, &1}))
    end)

    assert_receive {:live, :ready}
    assert_receive {:live, {:pcm, :system, <<1, 2>>}}
    assert_receive {:live, {:pcm, :microphone, <<3, 4>>}}
    assert_receive {:live, {:live_source_failed, :microphone, :conversion}}
    assert File.read!(Path.join(directory, "arguments")) == "--live\n#{directory}\n"
  end

  @tag :tmp_dir
  test "stops a live recording when its owner sends stop", %{tmp_dir: directory} do
    executable = Path.join(directory, "recorder")
    write_fake_recorder(executable, [<<1>>])
    receiver = self()

    task =
      Task.async(fn ->
        Recorder.record_live(executable, directory, &send(receiver, {:live, &1}), stop: :message)
      end)

    assert_receive {:live, :ready}, 1_000
    send(task.pid, :stop)

    assert :ok = Task.await(task)
    assert File.exists?(Path.join(directory, "system.m4a"))
    assert File.exists?(Path.join(directory, "microphone.m4a"))
  end

  @tag :tmp_dir
  test "notifies once on malformed transport and still waits for native finalization", %{
    tmp_dir: directory
  } do
    executable = Path.join(directory, "recorder")
    write_fake_recorder(executable, [<<1>>, <<9>>, <<8>>])
    receiver = self()

    capture_io("\n", fn ->
      assert :ok = Recorder.record_live(executable, directory, &send(receiver, {:live, &1}))
    end)

    assert_receive {:live, :ready}
    assert_receive {:live, {:live_transport_failed, :invalid_packet}}
    refute_receive {:live, _event}
    assert File.exists?(Path.join(directory, "system.m4a"))
    assert File.exists?(Path.join(directory, "microphone.m4a"))
  end

  defp write_fake_recorder(executable, payloads) do
    encoded_payloads =
      Enum.map_join(payloads, ", ", fn payload ->
        "bytes(#{inspect(:binary.bin_to_list(payload), charlists: :as_lists)})"
      end)

    File.write!(executable, """
    #!/usr/bin/python3
    import pathlib
    import signal
    import struct
    import sys
    import time

    output = pathlib.Path(sys.argv[-1])
    (output / "arguments").write_text("\\n".join(sys.argv[1:]) + "\\n")

    def stop(_signal, _frame):
        (output / "system.m4a").touch()
        (output / "microphone.m4a").touch()
        raise SystemExit(0)

    signal.signal(signal.SIGINT, stop)

    for payload in [#{encoded_payloads}]:
        sys.stdout.buffer.write(struct.pack(">I", len(payload)) + payload)
        sys.stdout.buffer.flush()

    time.sleep(0.5)
    raise SystemExit(2)
    """)

    File.chmod!(executable, 0o755)
  end
end
