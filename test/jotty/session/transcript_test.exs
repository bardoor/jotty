defmodule Jotty.Session.TranscriptTest do
  use ExUnit.Case, async: true

  alias Jotty.Recording
  alias Jotty.Session.Events.{TranscriptionFinished, UtteranceCompleted}
  alias Jotty.Session.{State, Transcript}
  alias Jotty.STT.TranscriptionChunk

  @tag :tmp_dir
  test "persists every completed utterance as a separate paragraph", %{tmp_dir: directory} do
    recording = %Recording{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }

    state = State.new(api_key: "unused", recorder: "/unused", recording: recording)

    state =
      Transcript.handle_message(
        %UtteranceCompleted{chunks: [chunk("First sentence.", "1")]},
        state
      )

    state =
      Transcript.handle_message(
        %UtteranceCompleted{chunks: [chunk("Second sentence.", "1"), chunk("Reply.", "2")]},
        state
      )

    Transcript.handle_message(%TranscriptionFinished{}, state)

    assert File.read!(recording.transcript) ==
             "Speaker 1: First sentence.\n\nSpeaker 1: Second sentence.\n\nSpeaker 2: Reply."
  end

  defp chunk(text, speaker) do
    %TranscriptionChunk{speaker: speaker, text: text, start_ms: 0, end_ms: 10}
  end
end
