defmodule Jotty.Desktop.ControllerTest do
  use ExUnit.Case, async: true

  alias Jotty.Desktop.Controller
  alias Jotty.Recording
  alias Jotty.Session.{RealtimeTranscriptionFailed, TranscriptionPreviewed, UtteranceCompleted}
  alias Jotty.STT.TranscriptionChunk

  @tag :tmp_dir
  test "starts, stops, and publishes the completed summary", %{tmp_dir: directory} do
    recording = recording(directory)
    File.write!(recording.summary, "# Summary\nA useful result.\n")
    test_pid = self()

    record = fn event_sink ->
      send(test_pid, {:recording_started, self(), event_sink})
      receive do: (:stop -> {:ok, recording})
    end

    {:ok, controller} = Controller.start_link(record: record)
    assert %{status: :idle} = Controller.attach(controller, self())

    assert :ok = Controller.start_recording(controller)
    assert_receive {:jotty_desktop_event, %{type: :state, status: :starting}}
    assert_receive {:recording_started, worker, ^controller}
    send(controller, {:jotty_session_event, :recording_started})
    assert_receive {:jotty_desktop_event, %{type: :state, status: :recording}}

    assert :ok = Controller.stop_recording(controller)
    assert_receive {:jotty_desktop_event, %{type: :state, status: :stopping}}

    assert_receive {:jotty_desktop_event,
                    %{
                      type: :summary_ready,
                      markdown: "# Summary\nA useful result.\n",
                      recording_directory: ^directory
                    }}

    refute Process.alive?(worker)

    assert %{status: :completed, summary: "# Summary\nA useful result.\n"} =
             Controller.attach(controller, self())
  end

  test "forwards realtime events and retains completed utterances" do
    record = fn event_sink ->
      send(self(), {:unused, event_sink})
      receive do: (:stop -> {:error, :stopped})
    end

    {:ok, controller} = Controller.start_link(record: record)
    Controller.attach(controller, self())
    :ok = Controller.start_recording(controller)
    assert_receive {:jotty_desktop_event, %{type: :state, status: :starting}}
    send(controller, {:jotty_session_event, :recording_started})
    assert_receive {:jotty_desktop_event, %{type: :state, status: :recording}}

    preview = %TranscriptionPreviewed{source: :system, chunks: [chunk("draft")]}
    completed = %UtteranceCompleted{source: :system, chunks: [chunk("done")]}
    send(controller, {:jotty_session_event, preview})
    send(controller, {:jotty_session_event, completed})

    assert_receive {:jotty_desktop_event, ^preview}
    assert_receive {:jotty_desktop_event, ^completed}

    assert %{utterances: [^completed], previews: %{system: nil}} =
             Controller.attach(controller, self())

    :ok = Controller.stop_recording(controller)
  end

  test "forwards and retains a non-fatal realtime transcription failure" do
    record = fn _event_sink -> receive do: (:stop -> {:error, :stopped}) end

    {:ok, controller} = Controller.start_link(record: record)
    Controller.attach(controller, self())
    :ok = Controller.start_recording(controller)
    assert_receive {:jotty_desktop_event, %{type: :state, status: :starting}}
    send(controller, {:jotty_session_event, :recording_started})
    assert_receive {:jotty_desktop_event, %{type: :state, status: :recording}}

    failure = %RealtimeTranscriptionFailed{source: :microphone, reason: :premature_close}
    send(controller, {:jotty_session_event, failure})

    assert_receive {:jotty_desktop_event,
                    %{type: :realtime_transcription_failed, source: :microphone, reason: ":premature_close"}}

    assert %{status: :recording, realtime_error: "microphone: :premature_close"} =
             Controller.attach(controller, self())

    :ok = Controller.stop_recording(controller)
  end

  defp recording(directory) do
    %Recording{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      mixed_audio: Path.join(directory, "audio.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }
  end

  defp chunk(text) do
    %TranscriptionChunk{speaker: "1", text: text, start_ms: 0, end_ms: 10}
  end
end
