defmodule Jotty.Desktop.ProtocolTest do
  use ExUnit.Case, async: true

  alias Jotty.Desktop.Protocol

  alias Jotty.Desktop.Commands.{
    AddContext,
    ChangeAlwaysOnTop,
    ChangeMicrophone,
    DeleteSession,
    ListMicrophones,
    ListSessions,
    OpenSession,
    RemoveContext,
    RenameSession,
    ReorderContexts,
    StartSession,
    StopSession
  }

  alias Jotty.Session.Presentation.Snapshot
  alias Jotty.Session.Events.{TranscriptionPreviewed, UtteranceCompleted}
  alias Jotty.STT.TranscriptionChunk

  test "decodes typed recording and settings commands" do
    context_id = "70bba3d8-cb9f-488a-b62e-da6247fc51b5"
    other_context_id = "6ca4adef-c4e8-4f70-b750-24824b642df3"

    assert %StartSession{} = Protocol.decode!(~s({"type":"start_session"}))
    assert %StopSession{} = Protocol.decode!(~s({"type":"stop_session"}))

    assert %ChangeAlwaysOnTop{enabled: true} =
             Protocol.decode!(~s({"type":"change_always_on_top","enabled":true}))

    assert %ChangeMicrophone{microphone_device_id: nil} =
             Protocol.decode!(~s({"type":"change_microphone","microphone_device_id":null}))

    assert %AddContext{path: "/project", approval: "signed"} =
             Protocol.decode!(~s({"type":"add_context","path":"/project","approval":"signed"}))

    assert %RemoveContext{id: ^context_id} =
             Protocol.decode!(~s({"type":"remove_context","id":"#{context_id}"}))

    assert %ReorderContexts{context_ids: [^context_id, ^other_context_id]} =
             Protocol.decode!(
               ~s({"type":"reorder_contexts","context_ids":["#{context_id}","#{other_context_id}"]})
             )

    assert %ListMicrophones{} = Protocol.decode!(~s({"type":"list_microphones"}))
  end

  test "decodes typed session catalog commands and rejects non-UUID ids" do
    id = "4b119ce6-d02b-41f7-9368-433f59db56a7"
    assert %ListSessions{} = Protocol.decode!(~s({"type":"list_sessions"}))
    assert %OpenSession{id: ^id} = Protocol.decode!(~s({"type":"open_session","id":"#{id}"}))

    assert %RenameSession{id: ^id, title: "Planning"} =
             Protocol.decode!(~s({"type":"rename_session","id":"#{id}","title":"Planning"}))

    assert %DeleteSession{id: ^id} = Protocol.decode!(~s({"type":"delete_session","id":"#{id}"}))
    assert_raise ArgumentError, fn -> Protocol.decode!(~s({"type":"open_session","id":"../../etc"})) end
  end

  test "encodes a transcription preview" do
    event = %TranscriptionPreviewed{chunks: [chunk("draft", 10, 20)]}

    payload =
      event
      |> Protocol.encode_event()
      |> Jason.decode!()

    assert payload == %{
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

    payload =
      event
      |> Protocol.encode_event()
      |> Jason.decode!()

    assert payload == %{
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

    payload =
      event
      |> Protocol.encode_event()
      |> Jason.decode!()

    assert payload == %{
             "type" => "summary_ready",
             "markdown" => "# Summary",
             "recording_directory" => "/recording"
           }

    activity = %{type: :hermes_activity, stage: :summary, status: :running, message: "Writing summary"}

    payload =
      activity
      |> Protocol.encode_event()
      |> Jason.decode!()

    assert payload == %{
             "type" => "hermes_activity",
             "stage" => "summary",
             "status" => "running",
             "message" => "Writing summary"
           }
  end

  test "encodes a non-fatal realtime transcription failure" do
    event = %{type: :realtime_transcription_failed, source: :system, reason: ":premature_close"}

    payload =
      event
      |> Protocol.encode_event()
      |> Jason.decode!()

    assert payload == %{
             "type" => "realtime_transcription_failed",
             "source" => "system",
             "reason" => ":premature_close"
           }
  end

  test "encodes a settings snapshot with unavailable persisted selections" do
    context_id = "70bba3d8-cb9f-488a-b62e-da6247fc51b5"

    snapshot = %Jotty.Settings.Snapshot{
      always_on_top: true,
      microphone_device_id: "missing",
      microphone_available: false,
      microphones: [%Jotty.Settings.Microphone{id: "mic-1", name: "Desk Mic"}],
      contexts: [
        %Jotty.Settings.ContextSnapshot{
          id: context_id,
          name: "project",
          path: "/project",
          position: 0,
          available: false
        }
      ]
    }

    event = %Jotty.Desktop.Events.SettingsChanged{snapshot: snapshot, error: nil}

    payload =
      event
      |> Protocol.encode_event()
      |> Jason.decode!()

    assert payload == %{
             "type" => "settings_changed",
             "always_on_top" => true,
             "microphone_device_id" => "missing",
             "microphone_available" => false,
             "microphones" => [%{"id" => "mic-1", "name" => "Desk Mic"}],
             "contexts" => [
               %{
                 "id" => context_id,
                 "name" => "project",
                 "path" => "/project",
                 "position" => 0,
                 "available" => false
               }
             ],
             "error" => nil
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
      activities: [
        %Jotty.Session.Events.HermesActivityObserved{
          stage: :summary,
          status: :running,
          message: "Writing summary"
        }
      ],
      recording_directory: nil
    }

    payload =
      snapshot
      |> Protocol.encode_event()
      |> Jason.decode!()

    assert payload == %{
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
             "activities" => [
               %{"stage" => "summary", "status" => "running", "message" => "Writing summary"}
             ],
             "recording_directory" => nil
           }
  end

  test "encodes typed session facts" do
    id = "4b119ce6-d02b-41f7-9368-433f59db56a7"
    metadata = %{id: id, title: "Planning", status: :completed}

    assert %Jotty.Desktop.Events.SessionOpened{session: metadata}
           |> Protocol.encode_event()
           |> Jason.decode!() == %{
             "type" => "session_opened",
             "session" => %{"id" => id, "title" => "Planning", "status" => "completed"}
           }

    assert %Jotty.Desktop.Events.SessionDeleted{id: id}
           |> Protocol.encode_event()
           |> Jason.decode!() == %{"type" => "session_deleted", "id" => id}
  end

  defp chunk(text, start_ms, end_ms) do
    %TranscriptionChunk{speaker: "1", text: text, start_ms: start_ms, end_ms: end_ms}
  end
end
