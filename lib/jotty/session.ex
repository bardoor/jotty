defmodule Jotty.Session do
  @moduledoc """
  Owns one recording's two realtime transcription streams and their events.
  """

  use GenServer

  require Logger

  alias Jotty.{Assistant, Recorder}

  alias Jotty.Session.{
    RealtimeTranscriptionFailed,
    TranscriptionPreviewed,
    UtteranceCompleted
  }

  alias Jotty.STT.Soniox.{Stream, WebSocketTransport}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @spec start(keyword()) :: GenServer.on_start()
  def start(options) do
    GenServer.start(__MODULE__, options)
  end

  @spec record(Path.t(), Path.t(), pid()) :: Recorder.result()
  def record(executable, directory, session) do
    record(executable, directory, session, [])
  end

  @spec record(Path.t(), Path.t(), pid(), keyword()) :: Recorder.result()
  def record(executable, directory, session, options) do
    result = Recorder.record_live(executable, directory, &live_event(session, &1), options)
    finish(session)
    GenServer.stop(session)
    result
  end

  @spec live_event(pid(), Jotty.Recorder.live_event()) :: :ok
  def live_event(session, event), do: GenServer.cast(session, {:live_event, event})

  @spec finish(pid()) :: :ok | {:error, term()}
  def finish(session), do: GenServer.call(session, :finish, :infinity)

  @impl GenServer
  def init(options) do
    api_key = Keyword.fetch!(options, :api_key)
    transport = Keyword.get(options, :transport, WebSocketTransport)
    transport_options = Keyword.get(options, :transport_options, [])
    shutdown_timeout = Keyword.get(options, :shutdown_timeout, 10_000)
    system = start_stream(:system, api_key, transport, transport_options)

    with {:ok, system} <- system do
      microphone = start_microphone(system, api_key, transport, transport_options)
      init_streams(microphone, system, options, shutdown_timeout)
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_cast({:live_event, :ready}, state) do
    publish_event(state.event_sink, :recording_started)
    {:noreply, state}
  end

  def handle_cast({:live_event, {:pcm, source, pcm}}, %{mode: :enabled} = state) do
    %{pid: stream} = Map.fetch!(state.streams, source)
    Stream.send_pcm(stream, pcm)
    {:noreply, state}
  end

  def handle_cast({:live_event, {:pcm, _source, _pcm}}, state), do: {:noreply, state}

  def handle_cast(
        {:live_event, {:live_source_failed, source, reason}},
        %{mode: :enabled} = state
      ) do
    reason = {:native, reason}
    {:noreply, disable(state, {:realtime_transcription_failed, source, reason}, source, reason)}
  end

  def handle_cast({:live_event, {:live_source_failed, _source, _reason}}, state),
    do: {:noreply, state}

  def handle_cast({:live_event, {:live_transport_failed, reason}}, %{mode: :enabled} = state) do
    state = disable(state, {:native_transport, reason}, nil, reason)
    {:noreply, state}
  end

  def handle_cast({:live_event, {:live_transport_failed, _reason}}, state), do: {:noreply, state}

  @impl GenServer
  def handle_call(:finish, _from, %{mode: :closed} = state), do: {:reply, :ok, state}

  def handle_call(:finish, _from, %{mode: :disabled} = state) do
    {:reply, {:error, :live_assistant_disabled}, state}
  end

  def handle_call(:finish, from, %{mode: :enabled} = state) do
    Enum.each(state.streams, fn {_source, %{pid: stream}} -> Stream.finish(stream) end)
    timer = Process.send_after(self(), :shutdown_timeout, state.shutdown_timeout)
    shutdown = %{from: from, timer: timer, open: MapSet.new(Map.keys(state.streams))}
    {:noreply, %{state | mode: :finishing, shutdown: shutdown}}
  end

  @impl GenServer
  def handle_info(
        {:stream_event, %RealtimeTranscriptionFailed{source: source, reason: reason}},
        %{mode: mode} = state
      )
      when mode in [:enabled, :finishing] do
    reason_with_source = {:realtime_transcription_failed, source, reason}
    {:noreply, disable(state, reason_with_source, source, reason)}
  end

  def handle_info({:stream_event, %TranscriptionPreviewed{} = event}, state) do
    publish_event(state.event_sink, event)
    {:noreply, state}
  end

  def handle_info({:stream_event, %UtteranceCompleted{} = event}, %{mode: mode} = state)
      when mode in [:enabled, :finishing] do
    publish_event(state.event_sink, event)
    submit_utterance(state.assistant, event)
    {:noreply, state}
  end

  def handle_info({:stream_event, %UtteranceCompleted{}}, state), do: {:noreply, state}
  def handle_info({:stream_event, %RealtimeTranscriptionFailed{}}, state), do: {:noreply, state}

  def handle_info({:stream_closed, source}, %{mode: :finishing} = state) do
    %{shutdown: shutdown} = state
    open = MapSet.delete(shutdown.open, source)
    streams = Map.delete(state.streams, source)

    if MapSet.size(open) == 0 do
      Process.cancel_timer(shutdown.timer)
      finish_assistant(state.assistant)
      GenServer.reply(shutdown.from, :ok)
      {:noreply, %{state | mode: :closed, streams: streams, shutdown: nil}}
    else
      {:noreply, %{state | streams: streams, shutdown: %{shutdown | open: open}}}
    end
  end

  def handle_info({:stream_closed, source}, %{mode: :enabled} = state) do
    reason = :unexpected_stream_close
    reason_with_source = {:realtime_transcription_failed, source, reason}
    {:noreply, disable(state, reason_with_source, source, reason)}
  end

  def handle_info({:stream_closed, _source}, state), do: {:noreply, state}

  def handle_info(:shutdown_timeout, %{mode: :finishing} = state) do
    state = disable(state, :shutdown_timeout, nil, :shutdown_timeout)
    {:noreply, state}
  end

  def handle_info(:shutdown_timeout, state), do: {:noreply, state}

  def handle_info({:DOWN, reference, :process, _pid, _exit_reason}, state) do
    source = source_by_reference(state.streams, reference)
    handle_stream_exit(source, state)
  end

  defp start_microphone(%{pid: system}, api_key, transport, transport_options) do
    result = start_stream(:microphone, api_key, transport, transport_options)
    stop_system_on_error(result, system)
  end

  defp init_streams({:error, reason}, _system, _options, _timeout), do: {:stop, reason}

  defp init_streams({:ok, microphone}, system, options, timeout) do
    state = %{
      assistant: Keyword.get(options, :assistant),
      event_sink: Keyword.get(options, :event_sink),
      mode: :enabled,
      streams: %{system: system, microphone: microphone},
      shutdown_timeout: timeout,
      shutdown: nil
    }

    {:ok, state}
  end

  defp start_stream(source, api_key, transport, transport_options) do
    case Stream.start(self(), source, api_key, transport, transport_options) do
      {:ok, pid} -> {:ok, %{pid: pid, reference: Process.monitor(pid)}}
      {:error, reason} -> {:error, {:stream_start, source, reason}}
    end
  end

  defp stop_system_on_error({:ok, _microphone} = result, _system), do: result

  defp stop_system_on_error({:error, _reason} = result, system) do
    Stream.stop(system)
    result
  end

  defp handle_stream_exit(nil, state), do: {:noreply, state}

  defp handle_stream_exit(source, %{mode: mode} = state)
       when mode in [:enabled, :finishing] do
    reason = :stream_exit
    reason_with_source = {:realtime_transcription_failed, source, reason}
    {:noreply, disable(state, reason_with_source, source, reason)}
  end

  defp handle_stream_exit(_source, state), do: {:noreply, state}

  defp disable(state, reason, source, log_reason) do
    Enum.each(state.streams, fn {_source, %{pid: stream}} -> Stream.stop(stream) end)
    disable_assistant(state.assistant)
    publish_event(state.event_sink, %RealtimeTranscriptionFailed{source: source, reason: log_reason})

    metadata = [component: :realtime_stt, reason: log_reason]
    metadata = if source == nil, do: metadata, else: Keyword.put(metadata, :source, source)
    Logger.error("live_assistant_disabled", metadata)

    if state.mode == :finishing do
      Process.cancel_timer(state.shutdown.timer)
      GenServer.reply(state.shutdown.from, {:error, reason})
    end

    %{state | mode: :disabled, shutdown: nil}
  end

  defp submit_utterance(nil, _event), do: :ok
  defp submit_utterance(assistant, event), do: Assistant.submit(assistant, event)

  defp publish_event(nil, _event), do: :ok
  defp publish_event(event_sink, event), do: send(event_sink, {:jotty_session_event, event})

  defp finish_assistant(nil), do: :ok
  defp finish_assistant(assistant), do: Assistant.finish(assistant)

  defp disable_assistant(nil), do: :ok
  defp disable_assistant(assistant), do: Assistant.disable(assistant)

  defp source_by_reference(streams, reference) do
    Enum.find_value(streams, fn {source, %{reference: stream_reference}} ->
      if stream_reference == reference, do: source
    end)
  end
end
