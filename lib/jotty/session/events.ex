defmodule Jotty.Session.Events do
  @moduledoc "Delivers typed session messages through handler-owned subscriptions."

  alias Jotty.Session.{Assistant, Lifecycle, Presentation, Recording, State, Summary, Transcript, Transcription}

  alias Jotty.Session.Events.{
    AudioReceived,
    ClientAttached,
    NativeAudioFailed,
    ProcessExited,
    RealtimeTranscriptionFailed,
    RecorderFinished,
    RecorderReady,
    RecordingStarted,
    SessionCompleted,
    SessionFailed,
    SessionStarting,
    SessionStopping,
    SessionTerminating,
    StartRequested,
    StopRequested,
    SummaryCompleted,
    SummaryFailed,
    SummaryReady,
    TranscriptFailed,
    TranscriptReady,
    TranscriptionFinished,
    TranscriptionPreviewed,
    TranscriptionTimeout,
    UtteranceCompleted
  }

  @handlers [Lifecycle, Recording, Transcription, Transcript, Assistant, Summary, Presentation]

  @type message ::
          AudioReceived.t()
          | ClientAttached.t()
          | NativeAudioFailed.t()
          | ProcessExited.t()
          | RealtimeTranscriptionFailed.t()
          | RecorderFinished.t()
          | RecorderReady.t()
          | RecordingStarted.t()
          | SessionCompleted.t()
          | SessionFailed.t()
          | SessionStarting.t()
          | SessionStopping.t()
          | SessionTerminating.t()
          | StartRequested.t()
          | StopRequested.t()
          | SummaryCompleted.t()
          | SummaryFailed.t()
          | SummaryReady.t()
          | TranscriptFailed.t()
          | TranscriptReady.t()
          | TranscriptionFinished.t()
          | TranscriptionPreviewed.t()
          | TranscriptionTimeout.t()
          | UtteranceCompleted.t()

  @spec publish(State.t(), message()) :: State.t()
  def publish(%State{} = state, message) do
    %{state | events: :queue.in(message, state.events)}
  end

  @spec dispatch(State.t(), message()) :: State.t()
  def dispatch(%State{} = state, message) do
    state
    |> publish(message)
    |> deliver_pending()
  end

  defp deliver_pending(%State{} = state) do
    case :queue.out(state.events) do
      {{:value, message}, events} ->
        message
        |> subscribers()
        |> Enum.reduce(%{state | events: events}, & &1.handle_message(message, &2))
        |> deliver_pending()

      {:empty, _events} ->
        state
    end
  end

  defp subscribers(message), do: Enum.filter(@handlers, &(message.__struct__ in &1.subscriptions()))
end
