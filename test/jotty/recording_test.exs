defmodule Jotty.RecordingTest do
  use ExUnit.Case, async: true

  alias Jotty.Recording

  @tag :tmp_dir
  test "creates one timestamped recording directory and exposes its artifacts", %{tmp_dir: home} do
    recorded_at = ~U[2026-09-21 17:45:00Z]

    recording = Recording.create!(home, recorded_at)

    expected_directory = Path.join([home, ".jotty", "recordings", "20260921-174500"])

    assert recording == %Recording{
             directory: expected_directory,
             system_audio: Path.join(expected_directory, "system.m4a"),
             microphone_audio: Path.join(expected_directory, "microphone.m4a"),
             mixed_audio: Path.join(expected_directory, "audio.m4a"),
             transcript: Path.join(expected_directory, "transcript.txt"),
             summary: Path.join(expected_directory, "summary.md")
           }

    assert File.dir?(expected_directory)
  end
end
