defmodule Jotty.RecordingTest do
  use ExUnit.Case, async: true

  alias Jotty.Recording

  @tag :tmp_dir
  test "creates one opaque recording directory and exposes every durable artifact", %{tmp_dir: home} do
    id = "4b119ce6-d02b-41f7-9368-433f59db56a7"
    recording = Recording.create!(home, ~U[2026-09-21 17:45:00Z], id)
    directory = Path.join([home, ".jotty", "recordings", id])

    assert recording == %Recording{
             directory: directory,
             system_audio: Path.join(directory, "system.m4a"),
             microphone_audio: Path.join(directory, "microphone.m4a"),
             aec_microphone_audio: Path.join(directory, "microphone-aec.wav"),
             playback_audio: Path.join(directory, "audio.m4a"),
             transcript: Path.join(directory, "transcript.txt"),
             summary: Path.join(directory, "summary.md")
           }

    assert File.dir?(directory)
  end
end
