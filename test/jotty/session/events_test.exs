defmodule Jotty.Session.EventsTest do
  use ExUnit.Case, async: true

  alias Jotty.Session.{Insights, Lifecycle, Presentation, Recording, Summary, Transcript, Transcription}

  alias Jotty.Session.Events.{
    AudioReceived,
    SessionStarting,
    SessionStopping,
    StartSession,
    TranscriptReady,
    TranscriptionFinished,
    UtteranceCompleted
  }

  test "handlers explicitly subscribe to requests, media, and facts" do
    assert subscribers(%StartSession{contexts: [], microphone_device_id: nil}) == [
             Lifecycle,
             Recording,
             Insights
           ]

    assert subscribers(%SessionStarting{}) == [Recording, Transcription, Insights, Presentation]
    assert subscribers(%SessionStopping{}) == [Recording, Presentation]
    assert subscribers(%AudioReceived{pcm: <<1, 2>>}) == [Transcription]

    assert subscribers(%UtteranceCompleted{chunks: []}) == [
             Transcript,
             Insights,
             Presentation
           ]

    assert subscribers(%TranscriptionFinished{}) == [Transcription, Transcript, Insights]

    assert subscribers(%TranscriptReady{path: "/tmp/transcript.txt"}) == [
             Lifecycle,
             Summary
           ]
  end

  defp subscribers(%message{}) do
    handlers = [Lifecycle, Recording, Transcription, Transcript, Insights, Summary, Presentation]
    Enum.filter(handlers, &(message in &1.subscriptions()))
  end
end
