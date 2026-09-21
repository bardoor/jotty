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
  test "sends SIGINT to the native recorder after Enter", %{tmp_dir: directory} do
    executable = Path.join(directory, "recorder")

    File.write!(executable, """
    #!/usr/bin/python3
    import pathlib
    import signal
    import sys
    import time

    output = pathlib.Path(sys.argv[1])

    def stop(_signal, _frame):
        (output / "system.m4a").touch()
        (output / "microphone.m4a").touch()
        raise SystemExit(0)

    signal.signal(signal.SIGINT, stop)
    print("ready", flush=True)
    time.sleep(0.5)
    raise SystemExit(2)
    """)

    File.chmod!(executable, 0o755)

    capture_io("\n", fn ->
      assert :ok = Recorder.record(executable, directory)
    end)

    assert File.exists?(Path.join(directory, "system.m4a"))
    assert File.exists?(Path.join(directory, "microphone.m4a"))
  end
end
