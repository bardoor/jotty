defmodule Jotty.STT.Soniox.Stream do
  @moduledoc false

  use GenServer
  require Logger

  alias Jotty.Session.Events.{
    RealtimeTranscriptionFailed,
    TranscriptionFinished,
    TranscriptionPreviewed,
    UtteranceCompleted
  }

  alias Jotty.Session.Server
  alias Jotty.STT.Soniox.{Adapter, Aggregator}

  @source :mixed

  @spec start(pid(), String.t(), module(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start(session, api_key, transport, transport_options) do
    GenServer.start(__MODULE__, {Logger.metadata(), session, api_key, transport, transport_options})
  end

  @spec send_pcm(pid(), nonempty_binary()) :: :ok
  def send_pcm(stream, pcm), do: GenServer.cast(stream, {:pcm, pcm})

  @spec finish(pid()) :: :ok
  def finish(stream), do: GenServer.cast(stream, :finish)

  @spec stop(pid()) :: :ok
  def stop(stream), do: GenServer.cast(stream, :stop)

  @impl GenServer
  def init({metadata, session, api_key, transport, transport_options}) do
    Logger.metadata(metadata)
    configuration = Jason.encode!(configuration(api_key))
    result = transport.start(self(), @source, configuration, transport_options)

    init(result, session, transport)
  end

  @impl GenServer
  def handle_cast({:pcm, pcm}, %{status: :streaming} = state) do
    result = state.transport.send_binary(state.transport_pid, pcm)
    handle_send(result, state, :streaming)
  end

  def handle_cast(:finish, %{status: :streaming} = state) do
    result = state.transport.finish(state.transport_pid)
    handle_send(result, state, :finishing)
  end

  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_info(
        {:soniox_transport, @source, {:text, payload}},
        %{status: status} = state
      )
      when status in [:streaming, :finishing] do
    response = Adapter.decode(payload)
    consume_response(response, state)
  end

  def handle_info({:soniox_transport, @source, :closed}, state) do
    stop_with_failure(state, :premature_close)
  end

  def handle_info({:soniox_transport, @source, {:error, reason}}, state) do
    stop_with_failure(state, {:transport, reason})
  end

  def handle_info(
        {:soniox_transport, @source, {:unexpected_frame, type}},
        state
      ) do
    stop_with_failure(state, {:unexpected_frame, type})
  end

  def handle_info(
        {:DOWN, reference, :process, transport_pid, _reason},
        %{transport_reference: reference, transport_pid: transport_pid} = state
      ) do
    stop_with_failure(state, :transport_exit)
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("stream_terminated", scope: :transcription, provider: :soniox, reason: inspect(reason))
    state.transport.stop(state.transport_pid)
  end

  defp consume_response(:finished, %{status: :streaming} = state) do
    stop_with_failure(state, :unexpected_finished)
  end

  defp consume_response(:finished, %{status: :finishing} = state) do
    Logger.info("terminal_response_received", scope: :transcription, provider: :soniox)
    Server.publish(state.session, %TranscriptionFinished{})
    {:stop, :normal, state}
  end

  defp consume_response({:error, reason}, state), do: stop_with_failure(state, reason)

  defp consume_response(response, state) do
    {aggregator, events} = Aggregator.consume(state.aggregator, response)
    Enum.each(events, &publish(&1, state))
    {:noreply, %{state | aggregator: aggregator}}
  end

  defp publish({:preview, chunks}, state) do
    event = %TranscriptionPreviewed{chunks: chunks}
    Server.publish(state.session, event)
  end

  defp publish({:completed, chunks}, state) do
    event = %UtteranceCompleted{chunks: chunks}
    Server.publish(state.session, event)
  end

  defp stop_with_failure(state, reason) do
    event = %RealtimeTranscriptionFailed{source: nil, reason: reason}
    Server.publish(state.session, event)
    {:stop, :normal, state}
  end

  defp init({:error, reason}, _session, _transport) do
    {:stop, {:transport_start, reason}}
  end

  defp init({:ok, transport_pid}, session, transport) do
    state = %{
      session: session,
      transport: transport,
      transport_pid: transport_pid,
      transport_reference: Process.monitor(transport_pid),
      aggregator: Aggregator.new(),
      status: :streaming
    }

    {:ok, state}
  end

  defp handle_send(:ok, state, :finishing) do
    Logger.info("finish_frame_sent", scope: :transcription, provider: :soniox)
    {:noreply, %{state | status: :finishing}}
  end

  defp handle_send(:ok, state, status), do: {:noreply, %{state | status: status}}

  defp handle_send({:error, reason}, state, _status) do
    stop_with_failure(state, {:send_failed, reason})
  end

  defp configuration(api_key) do
    %{
      api_key: api_key,
      model: "stt-rt-v5",
      audio_format: "pcm_s16le",
      sample_rate: 16_000,
      num_channels: 1,
      enable_speaker_diarization: true,
      enable_endpoint_detection: true,
      enable_language_identification: false
    }
  end
end
