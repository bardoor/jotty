defmodule Jotty.Desktop.Protocol do
  @moduledoc false

  alias Jotty.Desktop.Commands.{
    AddContext,
    ApproveTask,
    ChangeAlwaysOnTop,
    ChangeMicrophone,
    DeleteSession,
    DenyTask,
    ListMicrophones,
    ListSessions,
    OpenSession,
    RemoveContext,
    RenameSession,
    ReorderContexts,
    StartSession,
    StopSession
  }

  alias Jotty.Desktop.Events.{
    CommandRejected,
    SessionDeleted,
    SessionOpened,
    SessionRenamed,
    SessionsListed,
    SettingsChanged
  }

  alias Jotty.Session.Events.{TranscriptionPreviewed, UtteranceCompleted}
  alias Jotty.Session.Presentation.Snapshot, as: SessionSnapshot
  alias Jotty.Tasks.Card

  @spec decode!(String.t()) :: struct()
  def decode!(payload), do: command(Jason.decode!(payload))

  @spec encode_event(struct() | map()) :: String.t()
  def encode_event(%TranscriptionPreviewed{} = event) do
    event
    |> transcription_payload("transcription_previewed")
    |> Jason.encode!()
  end

  def encode_event(%UtteranceCompleted{} = event) do
    event
    |> transcription_payload("utterance_completed")
    |> Jason.encode!()
  end

  def encode_event(%SessionSnapshot{} = snapshot), do: encode_snapshot(snapshot)
  def encode_event(%{type: :snapshot} = snapshot), do: encode_snapshot(snapshot)

  def encode_event(%SettingsChanged{snapshot: snapshot, error: error}) do
    %{
      type: :settings_changed,
      always_on_top: snapshot.always_on_top,
      microphone_device_id: snapshot.microphone_device_id,
      microphone_available: snapshot.microphone_available,
      microphones: Enum.map(snapshot.microphones, &microphone_payload/1),
      contexts: Enum.map(snapshot.contexts, &context_payload/1),
      error: error
    }
    |> Jason.encode!()
  end

  def encode_event(%SessionsListed{sessions: sessions}),
    do: Jason.encode!(%{type: :sessions_listed, sessions: sessions})

  def encode_event(%SessionOpened{session: session}),
    do: Jason.encode!(%{type: :session_opened, session: session})

  def encode_event(%SessionRenamed{session: session}),
    do: Jason.encode!(%{type: :session_renamed, session: session})

  def encode_event(%SessionDeleted{id: id}), do: Jason.encode!(%{type: :session_deleted, id: id})

  def encode_event(%CommandRejected{command: command, reason: reason}) do
    Jason.encode!(%{type: :command_rejected, command: command, reason: reason})
  end

  def encode_event(%{type: type, card: %Card{} = card})
      when type in ~w(task_card_proposed task_card_updated)a do
    Jason.encode!(%{type: type, card: card_payload(card)})
  end

  def encode_event(%{type: :task_search_started, query: query}) do
    Jason.encode!(%{type: :task_search_started, query: query})
  end

  def encode_event(%{type: type} = event)
      when type in ~w(state summary_ready hermes_activity failed realtime_transcription_failed task_analysis_failed settings_invalid command_rejected)a,
      do: Jason.encode!(event)

  defp command(%{"type" => "start_session"}), do: %StartSession{}
  defp command(%{"type" => "stop_session"}), do: %StopSession{}
  defp command(%{"type" => "approve_task", "card_id" => card_id}), do: %ApproveTask{card_id: uuid!(card_id)}
  defp command(%{"type" => "deny_task", "card_id" => card_id}), do: %DenyTask{card_id: uuid!(card_id)}
  defp command(%{"type" => "list_sessions"}), do: %ListSessions{}
  defp command(%{"type" => "open_session", "id" => id}), do: %OpenSession{id: uuid!(id)}

  defp command(%{"type" => "rename_session", "id" => id, "title" => title}) when is_binary(title) do
    %RenameSession{id: uuid!(id), title: title}
  end

  defp command(%{"type" => "delete_session", "id" => id}), do: %DeleteSession{id: uuid!(id)}

  defp command(%{"type" => "change_always_on_top", "enabled" => enabled}) when is_boolean(enabled),
    do: %ChangeAlwaysOnTop{enabled: enabled}

  defp command(%{"type" => "change_microphone", "microphone_device_id" => device_id})
       when is_binary(device_id) or is_nil(device_id),
       do: %ChangeMicrophone{microphone_device_id: device_id}

  defp command(%{"type" => "add_context", "path" => path, "approval" => approval})
       when is_binary(path) and is_binary(approval),
       do: %AddContext{path: path, approval: approval}

  defp command(%{"type" => "remove_context", "id" => id}) do
    %RemoveContext{id: uuid!(id)}
  end

  defp command(%{"type" => "reorder_contexts", "context_ids" => ids}) when is_list(ids) do
    %ReorderContexts{context_ids: Enum.map(ids, &uuid!/1)}
  end

  defp command(%{"type" => "list_microphones"}), do: %ListMicrophones{}

  defp encode_snapshot(%{recording_directory: recording_directory} = snapshot) do
    payload = Map.put(snapshot_payload(snapshot), :recording_directory, recording_directory)
    Jason.encode!(payload)
  end

  defp encode_snapshot(snapshot), do: Jason.encode!(snapshot_payload(snapshot))

  defp snapshot_payload(snapshot) do
    %{
      type: snapshot.type,
      status: snapshot.status,
      utterances: Enum.map(snapshot.utterances, &transcription_payload(&1, "utterance_completed")),
      preview: preview_payload(snapshot.preview),
      realtime_error: snapshot.realtime_error,
      summary: snapshot.summary,
      activities: Enum.map(snapshot.activities, &activity_payload/1),
      task_cards: Enum.map(snapshot.task_cards, &card_payload/1),
      task_search_query: snapshot.task_search_query,
      task_error: snapshot.task_error
    }
  end

  defp transcription_payload(%{chunks: chunks}, type) do
    %{type: type, chunks: Enum.map(chunks, &chunk_payload/1)}
  end

  defp preview_payload(nil), do: nil
  defp preview_payload(event), do: transcription_payload(event, "transcription_previewed")

  defp microphone_payload(%{id: id, name: name}), do: %{id: id, name: name}

  defp context_payload(%{id: id, name: name, path: path, position: position, available: available}) do
    %{id: id, name: name, path: path, position: position, available: available}
  end

  defp activity_payload(%{stage: stage, status: status, message: message}) do
    %{stage: stage, status: status, message: message}
  end

  defp chunk_payload(%{speaker: speaker, text: text, start_ms: start_ms, end_ms: end_ms}) do
    %{speaker: speaker, text: text, start_ms: start_ms, end_ms: end_ms}
  end

  defp card_payload(%Card{} = card) do
    %{
      id: card.id,
      kind: card.kind,
      status: card.status,
      issue_id: card.issue_id,
      identifier: card.identifier,
      url: card.url,
      title: card.title,
      description: card.description,
      team: card.team,
      project: card.project,
      issue_status: card.issue_status,
      assignee: card.assignee,
      priority: card.priority,
      estimate: card.estimate,
      cycle_number: card.cycle_number,
      labels: card.labels,
      changes: Enum.map(card.changes, &change_payload/1),
      trigger: card.trigger,
      error: card.error
    }
  end

  defp change_payload(change), do: %{field: change.field, from: change.from, to: change.to}

  defp uuid!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> raise ArgumentError, "invalid session id"
    end
  end
end
