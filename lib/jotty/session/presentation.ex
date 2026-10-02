defmodule Jotty.Session.Presentation do
  @moduledoc "Owns the desktop projection and forwards observable session facts."

  @behaviour Jotty.Session.Consumer

  alias Jotty.Session.Events.{
    ClientAttached,
    RecordingStarted,
    RealtimeTranscriptionFailed,
    SessionCompleted,
    SessionFailed,
    SessionStarting,
    SessionStopping,
    SummaryReady,
    TranscriptionPreviewed,
    UtteranceCompleted
  }

  alias Jotty.Session.Presentation.Snapshot
  alias Jotty.Session.State

  @type status :: :idle | :starting | :recording | :stopping | :completed | :failed
  @type t :: %__MODULE__{
          client: pid() | nil,
          event_sinks: [pid()],
          status: status(),
          preview: TranscriptionPreviewed.t() | nil,
          utterances: [UtteranceCompleted.t()],
          realtime_error: String.t() | nil,
          summary: String.t() | nil,
          recording_directory: Path.t() | nil
        }

  defstruct client: nil,
            event_sinks: [],
            status: :idle,
            preview: nil,
            utterances: [],
            realtime_error: nil,
            summary: nil,
            recording_directory: nil

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{event_sinks: Keyword.get(options, :event_sinks, [])}
  end

  @impl true
  def subscriptions do
    [
      ClientAttached,
      SessionStarting,
      RecordingStarted,
      SessionStopping,
      TranscriptionPreviewed,
      UtteranceCompleted,
      RealtimeTranscriptionFailed,
      SummaryReady,
      SessionCompleted,
      SessionFailed
    ]
  end

  @spec snapshot(State.t()) :: Snapshot.t()
  def snapshot(%State{} = state) do
    %Snapshot{
      status: state.presentation.status,
      utterances: state.presentation.utterances,
      preview: state.presentation.preview,
      realtime_error: state.presentation.realtime_error,
      summary: state.presentation.summary,
      recording_directory: state.presentation.recording_directory
    }
  end

  @impl true
  def handle_message(%ClientAttached{client: client}, %State{} = state) do
    %{state | presentation: %{state.presentation | client: client}}
  end

  def handle_message(%SessionStarting{} = event, %State{} = state) do
    state
    |> update_status(:starting)
    |> emit_domain(event)
    |> emit_client(%{type: :state, status: :starting})
  end

  def handle_message(%RecordingStarted{} = event, %State{} = state) do
    state
    |> update_status(:recording)
    |> emit_domain(event)
    |> emit_client(%{type: :state, status: :recording})
  end

  def handle_message(%SessionStopping{} = event, %State{} = state) do
    state
    |> update_status(:stopping)
    |> emit_domain(event)
    |> emit_client(%{type: :state, status: :stopping})
  end

  def handle_message(%TranscriptionPreviewed{} = event, %State{} = state) do
    state = %{state | presentation: %{state.presentation | preview: event}}

    state
    |> emit_domain(event)
    |> emit_client(event)
  end

  def handle_message(%UtteranceCompleted{} = event, %State{} = state) do
    presentation = %{state.presentation | preview: nil, utterances: state.presentation.utterances ++ [event]}

    %{state | presentation: presentation}
    |> emit_domain(event)
    |> emit_client(event)
  end

  def handle_message(%RealtimeTranscriptionFailed{} = event, %State{} = state) do
    source = if event.source == nil, do: "transport", else: Atom.to_string(event.source)
    reason = inspect(event.reason)
    client_event = %{type: :realtime_transcription_failed, source: event.source, reason: reason}
    presentation = %{state.presentation | realtime_error: "#{source}: #{reason}"}

    %{state | presentation: presentation}
    |> emit_domain(event)
    |> emit_client(client_event)
  end

  def handle_message(%SummaryReady{recording: recording, markdown: markdown} = event, %State{} = state) do
    presentation = %{state.presentation | summary: markdown, recording_directory: recording.directory}
    client_event = %{type: :summary_ready, markdown: markdown, recording_directory: recording.directory}

    %{state | presentation: presentation}
    |> emit_domain(event)
    |> emit_client(client_event)
  end

  def handle_message(%SessionCompleted{} = event, %State{} = state) do
    state
    |> update_status(:completed)
    |> emit_domain(event)
  end

  def handle_message(%SessionFailed{reason: reason} = event, %State{} = state) do
    state
    |> update_status(:failed)
    |> emit_domain(event)
    |> emit_client(%{type: :failed, reason: inspect(reason)})
  end

  defp update_status(state, status) do
    %{state | presentation: %{state.presentation | status: status}}
  end

  defp emit_domain(%State{presentation: %__MODULE__{event_sinks: event_sinks}} = state, event) do
    Enum.each(event_sinks, &send(&1, {:jotty_session_event, event}))
    state
  end

  defp emit_client(%State{presentation: %__MODULE__{client: nil}} = state, _event), do: state

  defp emit_client(%State{presentation: %__MODULE__{client: client}} = state, event) do
    send(client, {:jotty_desktop_event, event})
    state
  end
end
