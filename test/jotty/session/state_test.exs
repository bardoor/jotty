defmodule Jotty.Session.StateTest do
  use ExUnit.Case, async: true

  alias Jotty.Recording, as: RecordingArtifact
  alias Jotty.Session.Events.StartSession

  alias Jotty.Session.{
    Insights,
    Lifecycle,
    Presentation,
    Recording,
    State,
    Summary,
    Transcript,
    Transcription
  }

  test "builds every handler-owned state slice through its struct constructor" do
    recording = %RecordingArtifact{
      directory: "/recording",
      system_audio: "/recording/system.m4a",
      microphone_audio: "/recording/microphone.m4a",
      transcript: "/recording/transcript.txt",
      summary: "/recording/summary.md"
    }

    options = [
      api_key: "key",
      contexts: ["context.md"],
      event_sinks: [self()],
      recorder: "/recorder",
      recorder_options: [sample_rate: 16_000],
      recording: recording,
      shutdown_timeout: 123,
      summarizer: FakeSummarizer,
      transport: FakeTransport,
      transport_options: [owner: self()]
    ]

    state = State.new(options)

    assert %Lifecycle{phase: :idle} = state.lifecycle

    assert %Recording{
             executable: "/recorder",
             recording: ^recording,
             options: [sample_rate: 16_000]
           } = state.recording

    assert %Transcription{
             api_key: "key",
             shutdown_timeout: 123,
             transport: FakeTransport,
             transport_options: [owner: owner]
           } = state.transcription

    assert owner == self()
    assert %Transcript{chunks: []} = state.transcript
    assert %Insights{contexts: [], pid: nil} = state.insights
    assert %Summary{summarizer: FakeSummarizer} = state.summary
    assert %Presentation{event_sinks: [sink], status: :idle} = state.presentation
    assert sink == self()
  end

  test "applies the typed recording settings snapshot to handler-owned slices" do
    recording = %RecordingArtifact{
      directory: "/recording",
      system_audio: "/recording/system.m4a",
      microphone_audio: "/recording/microphone.m4a",
      transcript: "/recording/transcript.txt",
      summary: "/recording/summary.md"
    }

    state = State.new(api_key: "key", recorder: "/recorder", recording: recording)
    command = %StartSession{contexts: ["/project"], microphone_device_id: "device-1"}
    state = Recording.handle_message(command, state)
    state = Insights.handle_message(command, state)

    assert state.recording.options[:microphone_device_id] == "device-1"
    assert state.insights.contexts == ["/project"]
  end
end
