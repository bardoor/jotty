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
  alias Jotty.STT.Soniox.{Adapter, Aggregator, Token}
  alias Jotty.TemporaryDirectory

  @bytes_per_ms 32
  @send_interval 100

  @spec start(pid(), String.t(), module(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start(session, api_key, transport, transport_options) do
    GenServer.start(__MODULE__, {Logger.metadata(), session, api_key, transport, transport_options})
  end

  @spec send_pcm(pid(), nonempty_binary()) :: :ok
  def send_pcm(stream, pcm), do: GenServer.cast(stream, {:pcm, pcm})

  @spec finish(pid(), non_neg_integer()) :: :ok
  def finish(stream, timeout), do: GenServer.cast(stream, {:finish, timeout})

  @spec stop(pid()) :: :ok
  def stop(stream), do: GenServer.cast(stream, :stop)

  @impl GenServer
  def init({metadata, session, api_key, transport, transport_options}) do
    Logger.metadata(metadata)
    configuration = Jason.encode!(configuration(api_key))

    case transport.start(self(), :mixed, configuration, transport_options) do
      {:ok, transport_pid} ->
        {:ok, init_stream(session, transport_pid, configuration, transport, transport_options)}

      {:error, reason} ->
        {:stop, {:transport_start, reason}}
    end
  end

  defp init_stream(session, transport_pid, configuration, transport, transport_options) do
    workspace = TemporaryDirectory.create!("jotty-transcription")
    buffer = File.open!(Path.join(workspace, "audio.pcm"), [:read, :write, :binary, :raw])

    state = %{
      session: session,
      transport: transport,
      transport_options: transport_options,
      configuration: configuration,
      transport_pid: transport_pid,
      transport_reference: Process.monitor(transport_pid),
      aggregator: %Aggregator{},
      status: :streaming,
      workspace: workspace,
      buffer: buffer,
      written_bytes: 0,
      sent_bytes: 0,
      confirmed_bytes: 0,
      connection_offset: 0,
      connected_at: System.monotonic_time(:millisecond) - @send_interval,
      retry_delay: 1_000,
      retry_timer: nil,
      send_timer: nil,
      finish_timer: nil,
      finish_timeout: nil
    }

    schedule_audio(state)
  end

  @impl GenServer
  def handle_cast({:pcm, pcm}, %{status: :streaming} = state) do
    case :file.pwrite(state.buffer, state.written_bytes, pcm) do
      :ok -> {:noreply, %{state | written_bytes: state.written_bytes + byte_size(pcm)}}
      {:error, reason} -> stop_with_failure(state, {:audio_buffer, reason})
    end
  end

  def handle_cast({:finish, timeout}, %{status: :streaming} = state) do
    {:noreply, %{state | status: :finishing, finish_timeout: timeout}}
  end

  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_info(
        {:soniox_transport, transport_pid, {:text, payload}},
        %{transport_pid: transport_pid} = state
      ) do
    response = Adapter.decode(payload)
    consume_response(response, state)
  end

  def handle_info({:soniox_transport, transport_pid, :closed}, %{transport_pid: transport_pid} = state) do
    reconnect(state, :premature_close)
  end

  def handle_info(
        {:soniox_transport, transport_pid, {:error, reason}},
        %{transport_pid: transport_pid} = state
      ) do
    reconnect(state, {:transport, reason})
  end

  def handle_info(
        {:soniox_transport, transport_pid, {:unexpected_frame, type}},
        %{transport_pid: transport_pid} = state
      ) do
    stop_with_failure(state, {:unexpected_frame, type})
  end

  def handle_info({:soniox_transport, _transport_pid, _message}, state), do: {:noreply, state}

  def handle_info(
        {:DOWN, reference, :process, transport_pid, _reason},
        %{transport_reference: reference, transport_pid: transport_pid} = state
      ) do
    reconnect(state, :transport_exit)
  end

  def handle_info({:timeout, timer, :reconnect}, %{retry_timer: timer} = state) do
    connect(%{state | retry_timer: nil})
  end

  def handle_info({:timeout, timer, :send_audio}, %{send_timer: timer} = state) do
    send_audio(%{state | send_timer: nil})
  end

  def handle_info({:timeout, timer, :finish}, %{finish_timer: timer} = state) do
    reconnect(state, :shutdown_timeout)
  end

  def handle_info({:timeout, _timer, _operation}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("stream_terminated", scope: :transcription, provider: :soniox, reason: inspect(reason))
    close_transport(state)
    File.close(state.buffer)
    File.rm_rf!(state.workspace)
  end

  defp consume_response({:finished, items, final_audio_proc_ms}, %{finish_timer: timer} = state)
       when is_reference(timer) do
    state = consume_batch(state, items, final_audio_proc_ms)
    complete_utterance(state)
    Logger.info("terminal_response_received", scope: :transcription, provider: :soniox)
    Server.publish(state.session, %TranscriptionFinished{})
    {:stop, :normal, state}
  end

  defp consume_response({:finished, items, final_audio_proc_ms}, state) do
    state
    |> consume_batch(items, final_audio_proc_ms)
    |> reconnect(:unexpected_finished)
  end

  defp consume_response({:error, {:provider_error, _code, type} = reason}, state)
       when type in ~w(
              request_timeout max_duration_reached service_unavailable
              limit_exceeded max_concurrent_connections_reached
            ) do
    reconnect(state, reason)
  end

  defp consume_response({:error, reason}, state), do: stop_with_failure(state, reason)

  defp consume_response({:batch, items, final_audio_proc_ms}, state) do
    {:noreply, consume_batch(state, items, final_audio_proc_ms)}
  end

  defp consume_batch(state, items, final_audio_proc_ms) do
    offset_ms = div(state.connection_offset, @bytes_per_ms)

    items =
      Enum.map(items, fn
        %Token{start_ms: start_ms, end_ms: end_ms} = token ->
          %{token | start_ms: start_ms + offset_ms, end_ms: end_ms + offset_ms}

        :endpoint ->
          :endpoint
      end)

    {aggregator, events} = Aggregator.consume(state.aggregator, {:batch, items})
    Enum.each(events, &publish(&1, state))
    confirmed_bytes = state.connection_offset + final_audio_proc_ms * @bytes_per_ms
    confirmed_bytes = max(state.confirmed_bytes, min(confirmed_bytes, state.sent_bytes))
    %{state | aggregator: aggregator, confirmed_bytes: confirmed_bytes, retry_delay: 1_000}
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

  defp connect(state) do
    case state.transport.start(self(), :mixed, state.configuration, state.transport_options) do
      {:ok, transport_pid} ->
        Logger.info("connected", scope: :transcription, provider: :soniox)

        state = %{
          state
          | transport_pid: transport_pid,
            transport_reference: Process.monitor(transport_pid),
            connection_offset: state.confirmed_bytes,
            sent_bytes: state.confirmed_bytes,
            connected_at: System.monotonic_time(:millisecond) - @send_interval
        }

        {:noreply, schedule_audio(state)}

      {:error, reason} ->
        reconnect(state, {:transport_start, reason})
    end
  end

  defp reconnect(state, reason) do
    Logger.warning("reconnecting",
      scope: :transcription,
      provider: :soniox,
      reason: inspect(reason),
      retry_delay_ms: state.retry_delay,
      pending_audio_ms: div(state.written_bytes - state.confirmed_bytes, @bytes_per_ms)
    )

    close_transport(state)
    cancel_timer(state.send_timer)
    cancel_timer(state.finish_timer)
    complete_utterance(state)
    Server.publish(state.session, %TranscriptionPreviewed{chunks: []})
    timer = :erlang.start_timer(state.retry_delay, self(), :reconnect)

    state = %{
      state
      | transport_pid: nil,
        transport_reference: nil,
        aggregator: %Aggregator{},
        retry_timer: timer,
        send_timer: nil,
        finish_timer: nil,
        retry_delay: min(state.retry_delay * 2, 10_000)
    }

    {:noreply, state}
  end

  defp send_audio(%{status: :finishing, written_bytes: size, sent_bytes: size} = state) do
    case state.transport.finish(state.transport_pid) do
      :ok ->
        Logger.info("finish_frame_sent", scope: :transcription, provider: :soniox)
        timer = :erlang.start_timer(state.finish_timeout, self(), :finish)
        {:noreply, %{state | finish_timer: timer}}

      {:error, reason} ->
        reconnect(state, {:send_failed, reason})
    end
  end

  defp send_audio(state) do
    elapsed = System.monotonic_time(:millisecond) - state.connected_at
    allowed_bytes = state.connection_offset + elapsed * @bytes_per_ms
    size = min(state.written_bytes, allowed_bytes) - state.sent_bytes
    size = min(size, @send_interval * @bytes_per_ms)
    send_audio(state, size)
  end

  defp send_audio(state, 0), do: {:noreply, schedule_audio(state)}

  defp send_audio(state, size) do
    case :file.pread(state.buffer, state.sent_bytes, size) do
      {:ok, pcm} -> send_buffered(state, pcm)
      {:error, reason} -> stop_with_failure(state, {:audio_buffer, reason})
    end
  end

  defp send_buffered(state, pcm) do
    case state.transport.send_binary(state.transport_pid, pcm) do
      :ok -> {:noreply, schedule_audio(%{state | sent_bytes: state.sent_bytes + byte_size(pcm)})}
      {:error, reason} -> reconnect(state, {:send_failed, reason})
    end
  end

  defp schedule_audio(state) do
    elapsed = System.monotonic_time(:millisecond) - state.connected_at
    delay = @send_interval - rem(elapsed, @send_interval)
    %{state | send_timer: :erlang.start_timer(delay, self(), :send_audio)}
  end

  defp complete_utterance(state) do
    {_aggregator, events} = Aggregator.consume(state.aggregator, :finished)
    Enum.each(events, &publish(&1, state))
  end

  defp close_transport(%{transport_pid: nil}), do: :ok

  defp close_transport(state) do
    Process.demonitor(state.transport_reference, [:flush])
    state.transport.stop(state.transport_pid)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

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
