defmodule Jotty.Session.Transcription do
  @moduledoc "Owns the single realtime Soniox stream."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Session.Events

  alias Jotty.Session.Events.{
    AudioReceived,
    NativeAudioFailed,
    ProcessExited,
    RealtimeTranscriptionFailed,
    RecorderFinished,
    SessionFailed,
    SessionStarting,
    SessionTerminating,
    TranscriptionFinished,
    TranscriptionTimeout
  }

  alias Jotty.Session.{State}
  alias Jotty.STT.Soniox.Stream

  @type phase :: :idle | :streaming | :finishing | :closed | :failed
  @type t :: %__MODULE__{
          api_key: String.t(),
          transport: module(),
          transport_options: keyword(),
          shutdown_timeout: non_neg_integer(),
          stream: pid() | nil,
          reference: reference() | nil,
          timer: reference() | nil,
          phase: phase()
        }

  @enforce_keys [:api_key, :transport]
  defstruct [
    :api_key,
    :transport,
    transport_options: [],
    shutdown_timeout: 10_000,
    stream: nil,
    reference: nil,
    timer: nil,
    phase: :idle
  ]

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{
      api_key: Keyword.fetch!(options, :api_key),
      transport: Keyword.get(options, :transport, Jotty.STT.Soniox.WebSocketTransport),
      transport_options: Keyword.get(options, :transport_options, []),
      shutdown_timeout: Keyword.get(options, :shutdown_timeout, 10_000)
    }
  end

  @impl true
  def subscriptions do
    [
      AudioReceived,
      NativeAudioFailed,
      SessionStarting,
      RecorderFinished,
      TranscriptionFinished,
      RealtimeTranscriptionFailed,
      SessionFailed,
      SessionTerminating,
      TranscriptionTimeout,
      ProcessExited
    ]
  end

  @impl true
  def handle_message(%SessionStarting{}, %State{} = state) do
    case start(state) do
      {:ok, state} -> state
      {:error, reason, state} -> Events.publish(state, %SessionFailed{reason: reason})
    end
  end

  def handle_message(%AudioReceived{pcm: pcm}, %State{transcription: %__MODULE__{phase: :streaming}} = state) do
    Stream.send_pcm(state.transcription.stream, pcm)
    state
  end

  def handle_message(%AudioReceived{}, %State{} = state), do: state

  def handle_message(%NativeAudioFailed{source: source, reason: reason}, %State{} = state) do
    event = if source == nil, do: "transport_failed", else: "source_failed"
    Logger.error(event, scope: :recording, source: source, reason: inspect(reason))
    Events.publish(state, %RealtimeTranscriptionFailed{source: source, reason: reason})
  end

  def handle_message(%RecorderFinished{}, %State{transcription: %__MODULE__{phase: :streaming}} = state) do
    Logger.info("finishing", scope: :transcription, provider: :soniox)
    Stream.finish(state.transcription.stream)
    timer = Process.send_after(self(), %TranscriptionTimeout{}, state.transcription.shutdown_timeout)
    transcription = %{state.transcription | phase: :finishing, timer: timer}
    %{state | transcription: transcription}
  end

  def handle_message(%RecorderFinished{}, %State{} = state), do: state

  def handle_message(%TranscriptionFinished{}, %State{} = state) do
    Logger.info("finished", scope: :transcription, provider: :soniox)
    cancel_timer(state.transcription.timer)
    transcription = %{state.transcription | stream: nil, reference: nil, timer: nil, phase: :closed}
    %{state | transcription: transcription}
  end

  def handle_message(
        %RealtimeTranscriptionFailed{} = failure,
        %State{transcription: %__MODULE__{phase: phase}} = state
      )
      when phase in [:streaming, :finishing] do
    Stream.stop(state.transcription.stream)
    cancel_timer(state.transcription.timer)
    Logger.error("failed", scope: :transcription, provider: :soniox, reason: inspect(failure.reason))
    transcription = %{state.transcription | stream: nil, reference: nil, timer: nil, phase: :failed}
    %{state | transcription: transcription}
  end

  def handle_message(%RealtimeTranscriptionFailed{}, %State{} = state), do: state

  def handle_message(
        %TranscriptionTimeout{},
        %State{transcription: %__MODULE__{phase: :finishing}} = state
      ) do
    Logger.error("timeout",
      scope: :transcription,
      provider: :soniox,
      timeout_ms: state.transcription.shutdown_timeout
    )

    Events.publish(state, %RealtimeTranscriptionFailed{source: nil, reason: :shutdown_timeout})
  end

  def handle_message(%TranscriptionTimeout{}, %State{} = state), do: state

  def handle_message(
        %ProcessExited{reference: reference, pid: stream},
        %State{transcription: %__MODULE__{reference: reference, stream: stream, phase: phase}} = state
      )
      when phase in [:streaming, :finishing] do
    Events.publish(state, %RealtimeTranscriptionFailed{source: nil, reason: :stream_exit})
  end

  def handle_message(%ProcessExited{}, %State{} = state), do: state

  def handle_message(%SessionFailed{}, %State{} = state), do: stop(state)

  def handle_message(%SessionTerminating{}, %State{transcription: %__MODULE__{stream: stream}} = state)
      when is_pid(stream) do
    Stream.stop(stream)
    state
  end

  def handle_message(%SessionTerminating{}, %State{} = state), do: state

  defp start(%State{} = state) do
    transcription = state.transcription

    Logger.info("starting",
      scope: :transcription,
      provider: :soniox,
      model: "stt-rt-v5",
      sample_rate: 16_000,
      num_channels: 1,
      audio_format: "pcm_s16le"
    )

    case Stream.start(self(), transcription.api_key, transcription.transport, transcription.transport_options) do
      {:ok, stream} ->
        Logger.info("started", scope: :transcription, provider: :soniox)
        next = %{transcription | stream: stream, reference: Process.monitor(stream), phase: :streaming}
        {:ok, %{state | transcription: next}}

      {:error, reason} ->
        Logger.error("failed",
          scope: :transcription,
          provider: :soniox,
          reason: inspect({:stream_start, reason})
        )

        {:error, {:stream_start, reason}, state}
    end
  end

  defp stop(%State{transcription: %__MODULE__{stream: stream}} = state) when is_pid(stream) do
    Stream.stop(stream)
    cancel_timer(state.transcription.timer)
    transcription = %{state.transcription | stream: nil, reference: nil, timer: nil, phase: :failed}
    %{state | transcription: transcription}
  end

  defp stop(%State{} = state), do: state

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
end
