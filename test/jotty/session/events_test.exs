defmodule Jotty.Session.EventsTest do
  use ExUnit.Case, async: true

  alias Jotty.Session.{Assistant, Lifecycle, Presentation, Recording, Summary, Transcript, Transcription}

  alias Jotty.Session.Events.{
    AudioReceived,
    SessionStarting,
    SessionStopping,
    StartRequested,
    TranscriptReady,
    TranscriptionFinished,
    UtteranceCompleted
  }

  @handlers [Lifecycle, Recording, Transcription, Transcript, Assistant, Summary, Presentation]

  test "handlers explicitly subscribe to requests, media, and facts" do
    assert subscribers(%StartRequested{}) == [Lifecycle]
    assert subscribers(%SessionStarting{}) == [Recording, Transcription, Assistant, Presentation]
    assert subscribers(%SessionStopping{}) == [Recording, Presentation]
    assert subscribers(%AudioReceived{pcm: <<1, 2>>}) == [Transcription]

    assert subscribers(%UtteranceCompleted{chunks: []}) == [
             Transcript,
             Assistant,
             Presentation
           ]

    assert subscribers(%TranscriptionFinished{}) == [Transcription, Transcript, Assistant]

    assert subscribers(%TranscriptReady{path: "/tmp/transcript.txt"}) == [
             Lifecycle,
             Summary
           ]
  end

  test "every request has exactly one subscriber" do
    {:ok, modules} = :application.get_key(:jotty, :modules)

    request_modules =
      Enum.filter(modules, fn module ->
        module
        |> Module.split()
        |> List.last()
        |> String.ends_with?("Requested")
      end)

    assert Enum.all?(request_modules, fn request ->
             request
             |> struct()
             |> subscribers()
             |> length()
             |> Kernel.==(1)
           end)
  end

  defp subscribers(%message{}) do
    Enum.filter(@handlers, &(message in &1.subscriptions()))
  end
end
