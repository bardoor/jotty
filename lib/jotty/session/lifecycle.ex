defmodule Jotty.Session.Lifecycle do
  @moduledoc "Owns session startup, stop coordination, and terminal results."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Session.{Events, State}

  alias Jotty.Session.Events.{
    RealtimeTranscriptionFailed,
    RecorderFinished,
    RecordingStarted,
    SessionCompleted,
    SessionFailed,
    SessionStarting,
    SessionStopping,
    StartSession,
    StopSession,
    SummaryFailed,
    SummaryReady,
    TranscriptFailed,
    TranscriptReady
  }

  @type phase :: :idle | :starting | :running | :stopping | :completed | :failed
  @type t :: %__MODULE__{
          phase: phase(),
          recorder_result: nil | Jotty.Recorder.result(),
          transcription_failure: nil | term()
        }

  defstruct phase: :idle, recorder_result: nil, transcription_failure: nil

  @impl true
  def subscriptions do
    [
      StartSession,
      StopSession,
      RecordingStarted,
      RecorderFinished,
      RealtimeTranscriptionFailed,
      TranscriptReady,
      TranscriptFailed,
      SummaryReady,
      SummaryFailed,
      SessionFailed
    ]
  end

  @impl true
  def handle_message(%StartSession{contexts: contexts}, %State{lifecycle: %__MODULE__{phase: :idle}} = state) do
    case Jotty.Insights.validate_contexts(contexts) do
      :ok ->
        Logger.info("starting", scope: :session)

        state
        |> put_phase(:starting)
        |> Events.publish(%SessionStarting{})

      {:error, reason} ->
        Events.publish(state, %SessionFailed{reason: reason})
    end
  end

  def handle_message(%StopSession{}, %State{lifecycle: %__MODULE__{phase: :running}} = state) do
    Logger.info("stopping", scope: :session)

    state
    |> put_phase(:stopping)
    |> Events.publish(%SessionStopping{})
  end

  def handle_message(%RecordingStarted{}, %State{lifecycle: %__MODULE__{phase: :starting}} = state) do
    Logger.info("recording", scope: :session)
    put_phase(state, :running)
  end

  def handle_message(%RecorderFinished{result: result}, %State{} = state) do
    lifecycle = %{state.lifecycle | recorder_result: result}
    state = %{state | lifecycle: lifecycle}

    if state.lifecycle.transcription_failure == nil do
      state
    else
      Events.publish(state, %SessionFailed{
        reason: {:realtime_transcription_failed, state.lifecycle.transcription_failure}
      })
    end
  end

  def handle_message(%RealtimeTranscriptionFailed{} = failure, %State{} = state) do
    lifecycle = %{state.lifecycle | transcription_failure: failure.reason}
    state = %{state | lifecycle: lifecycle}

    if state.lifecycle.recorder_result == nil do
      state
    else
      Events.publish(state, %SessionFailed{reason: {:realtime_transcription_failed, failure.reason}})
    end
  end

  def handle_message(
        %TranscriptReady{},
        %State{lifecycle: %__MODULE__{recorder_result: {:error, reason}}} = state
      ) do
    Events.publish(state, %SessionFailed{reason: reason})
  end

  def handle_message(%TranscriptFailed{reason: reason}, %State{} = state) do
    Events.publish(state, %SessionFailed{reason: {:transcript, reason}})
  end

  def handle_message(%SummaryReady{recording: recording}, %State{} = state) do
    Logger.info("completed", scope: :session)
    result = {:ok, recording}
    lifecycle = %{state.lifecycle | phase: :completed}
    state = %{state | lifecycle: lifecycle}
    Events.publish(state, %SessionCompleted{result: result})
  end

  def handle_message(%SummaryFailed{reason: reason}, %State{} = state) do
    Events.publish(state, %SessionFailed{reason: reason})
  end

  def handle_message(%SessionFailed{}, %State{} = state) do
    %{state | lifecycle: %{state.lifecycle | phase: :failed}}
  end

  def handle_message(_message, %State{} = state), do: state

  defp put_phase(state, phase), do: %{state | lifecycle: %{state.lifecycle | phase: phase}}
end
