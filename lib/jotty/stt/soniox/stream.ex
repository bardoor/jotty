defmodule Jotty.STT.Soniox.Stream do
  @moduledoc false

  use GenServer

  alias Jotty.Session.{RealtimeTranscriptionFailed, TranscriptionPreviewed, UtteranceCompleted}
  alias Jotty.STT.Soniox.{Adapter, Aggregator}

  @spec start(pid(), :system | :microphone, String.t(), module(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start(session, source, api_key, transport, transport_options) do
    GenServer.start(__MODULE__, {session, source, api_key, transport, transport_options})
  end

  @spec send_pcm(pid(), nonempty_binary()) :: :ok
  def send_pcm(stream, pcm), do: GenServer.cast(stream, {:pcm, pcm})

  @spec finish(pid()) :: :ok
  def finish(stream), do: GenServer.cast(stream, :finish)

  @spec stop(pid()) :: :ok
  def stop(stream), do: GenServer.cast(stream, :stop)

  @impl GenServer
  def init({session, source, api_key, transport, transport_options}) do
    configuration = Jason.encode!(configuration(api_key))
    result = transport.start(self(), source, configuration, transport_options)

    init(result, session, source, transport)
  end

  @impl GenServer
  def handle_cast({:pcm, pcm}, %{status: :streaming} = state) do
    result = state.transport.send_binary(state.transport_pid, pcm)
    handle_send(result, state, :streaming)
  end

  def handle_cast(:finish, %{status: :streaming} = state) do
    result = state.transport.send_binary(state.transport_pid, <<>>)
    handle_send(result, state, :finishing)
  end

  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_info(
        {:soniox_transport, source, {:text, payload}},
        %{source: source, status: status} = state
      )
      when status in [:streaming, :finishing] do
    response = Adapter.decode(payload)
    consume_response(response, state)
  end

  def handle_info(
        {:soniox_transport, source, {:text, _payload}},
        %{source: source, status: :finished} = state
      ) do
    stop_with_failure(state, :response_after_finished)
  end

  def handle_info(
        {:soniox_transport, source, :closed},
        %{source: source, status: :finished} = state
      ) do
    send(state.session, {:stream_closed, source})
    {:stop, :normal, state}
  end

  def handle_info({:soniox_transport, source, :closed}, %{source: source} = state) do
    stop_with_failure(state, :premature_close)
  end

  def handle_info({:soniox_transport, source, {:error, reason}}, %{source: source} = state) do
    stop_with_failure(state, {:transport, reason})
  end

  def handle_info(
        {:soniox_transport, source, {:unexpected_frame, type}},
        %{source: source} = state
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
  def terminate(_reason, state) do
    state.transport.stop(state.transport_pid)
  end

  defp consume_response(:finished, %{status: :streaming} = state) do
    stop_with_failure(state, :unexpected_finished)
  end

  defp consume_response({:error, reason}, state), do: stop_with_failure(state, reason)

  defp consume_response(response, state) do
    {aggregator, events} = Aggregator.consume(state.aggregator, response)
    Enum.each(events, &publish(&1, state))
    status = if response == :finished, do: :finished, else: state.status
    {:noreply, %{state | aggregator: aggregator, status: status}}
  end

  defp publish({:preview, chunks}, state) do
    event = %TranscriptionPreviewed{source: state.source, chunks: chunks}
    send(state.session, {:stream_event, event})
  end

  defp publish({:completed, chunks}, state) do
    event = %UtteranceCompleted{source: state.source, chunks: chunks}
    send(state.session, {:stream_event, event})
  end

  defp stop_with_failure(state, reason) do
    event = %RealtimeTranscriptionFailed{source: state.source, reason: reason}
    send(state.session, {:stream_event, event})
    {:stop, :normal, state}
  end

  defp init({:error, reason}, _session, _source, _transport) do
    {:stop, {:transport_start, reason}}
  end

  defp init({:ok, transport_pid}, session, source, transport) do
    state = %{
      session: session,
      source: source,
      transport: transport,
      transport_pid: transport_pid,
      transport_reference: Process.monitor(transport_pid),
      aggregator: Aggregator.new(),
      status: :streaming
    }

    {:ok, state}
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
