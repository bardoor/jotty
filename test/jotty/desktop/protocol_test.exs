defmodule Jotty.Desktop.ProtocolTest do
  use ExUnit.Case, async: true

  alias Jotty.Desktop.Protocol
  alias Jotty.Session.Presentation.Snapshot
  alias Jotty.Session.Events.{TranscriptionPreviewed, UtteranceCompleted}
  alias Jotty.STT.TranscriptionChunk

  test "decodes recording commands" do
    assert Protocol.decode!(~s({"type":"start"})) == :start
    assert Protocol.decode!(~s({"type":"stop"})) == :stop
  end

  test "encodes a transcription preview" do
    event = %TranscriptionPreviewed{chunks: [chunk("draft", 10, 20)]}

    assert event |> Protocol.encode_event() |> Jason.decode!() == %{
             "type" => "transcription_previewed",
             "chunks" => [
               %{
                 "speaker" => "1",
                 "text" => "draft",
                 "start_ms" => 10,
                 "end_ms" => 20
               }
             ]
           }
  end

  test "encodes a completed utterance" do
    event = %UtteranceCompleted{chunks: [chunk("done", 20, 30)]}

    assert event |> Protocol.encode_event() |> Jason.decode!() == %{
             "type" => "utterance_completed",
             "chunks" => [
               %{
                 "speaker" => "1",
                 "text" => "done",
                 "start_ms" => 20,
                 "end_ms" => 30
               }
             ]
           }
  end

  test "encodes desktop state and summary events" do
    assert %{type: :state, status: :recording}
           |> Protocol.encode_event()
           |> Jason.decode!() == %{"type" => "state", "status" => "recording"}

    event = %{type: :summary_ready, markdown: "# Summary", recording_directory: "/recording"}

    assert event |> Protocol.encode_event() |> Jason.decode!() == %{
             "type" => "summary_ready",
             "markdown" => "# Summary",
             "recording_directory" => "/recording"
           }
  end

  test "encodes a non-fatal realtime transcription failure" do
    event = %{type: :realtime_transcription_failed, source: :system, reason: ":premature_close"}

    assert event |> Protocol.encode_event() |> Jason.decode!() == %{
             "type" => "realtime_transcription_failed",
             "source" => "system",
             "reason" => ":premature_close"
           }
  end

  test "encodes a reconnect snapshot with completed and provisional transcript" do
    completed = %UtteranceCompleted{chunks: [chunk("done", 0, 10)]}
    preview = %TranscriptionPreviewed{chunks: [chunk("draft", 10, 20)]}

    snapshot = %Snapshot{
      status: :recording,
      utterances: [completed],
      preview: preview,
      realtime_error: "system: :premature_close",
      summary: nil,
      recording_directory: nil
    }

    assert snapshot |> Protocol.encode_event() |> Jason.decode!() == %{
             "type" => "snapshot",
             "status" => "recording",
             "utterances" => [
               %{
                 "type" => "utterance_completed",
                 "chunks" => [
                   %{
                     "speaker" => "1",
                     "text" => "done",
                     "start_ms" => 0,
                     "end_ms" => 10
                   }
                 ]
               }
             ],
             "preview" => %{
               "type" => "transcription_previewed",
               "chunks" => [
                 %{
                   "speaker" => "1",
                   "text" => "draft",
                   "start_ms" => 10,
                   "end_ms" => 20
                 }
               ]
             },
             "realtime_error" => "system: :premature_close",
             "summary" => nil,
             "recording_directory" => nil
           }
  end

  defp chunk(text, start_ms, end_ms) do
    %TranscriptionChunk{speaker: "1", text: text, start_ms: start_ms, end_ms: end_ms}
  end
end
