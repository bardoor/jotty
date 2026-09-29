defmodule Jotty.Desktop.Controller do
  @moduledoc false

  use GenServer

  alias Jotty.Session.{RealtimeTranscriptionFailed, TranscriptionPreviewed, UtteranceCompleted}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @spec attach(pid(), pid()) :: map()
  def attach(controller, client), do: GenServer.call(controller, {:attach, client})

  @spec start_recording(pid()) :: :ok | {:error, :not_idle}
  def start_recording(controller), do: GenServer.call(controller, :start_recording)

  @spec stop_recording(pid()) :: :ok | {:error, :not_recording}
  def stop_recording(controller), do: GenServer.call(controller, :stop_recording)

  @impl GenServer
  def init(options) do
    state = %{
      client: nil,
      previews: %{system: nil, microphone: nil},
      realtime_error: nil,
      record: Keyword.fetch!(options, :record),
      status: :idle,
      summary: nil,
      recording_directory: nil,
      utterances: [],
      worker: nil,
      worker_reference: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:attach, client}, _from, state) do
    {:reply, snapshot(state), %{state | client: client}}
  end

  def handle_call(:start_recording, _from, %{status: :idle} = state) do
    controller = self()

    {worker, reference} =
      spawn_monitor(fn ->
        result = state.record.(controller)
        send(controller, {:recording_finished, self(), result})
      end)

    event = %{type: :state, status: :starting}
    publish(state.client, event)
    {:reply, :ok, %{state | status: :starting, worker: worker, worker_reference: reference}}
  end

  def handle_call(:start_recording, _from, state), do: {:reply, {:error, :not_idle}, state}

  def handle_call(:stop_recording, _from, %{status: :recording} = state) do
    send(state.worker, :stop)
    event = %{type: :state, status: :stopping}
    publish(state.client, event)
    {:reply, :ok, %{state | status: :stopping}}
  end

  def handle_call(:stop_recording, _from, state),
    do: {:reply, {:error, :not_recording}, state}

  @impl GenServer
  def handle_info({:jotty_session_event, :recording_started}, %{status: :starting} = state) do
    event = %{type: :state, status: :recording}
    publish(state.client, event)
    {:noreply, %{state | status: :recording}}
  end

  def handle_info({:jotty_session_event, %TranscriptionPreviewed{} = event}, state) do
    publish(state.client, event)
    previews = Map.put(state.previews, event.source, event)
    {:noreply, %{state | previews: previews}}
  end

  def handle_info({:jotty_session_event, %UtteranceCompleted{} = event}, state) do
    publish(state.client, event)
    previews = Map.put(state.previews, event.source, nil)
    {:noreply, %{state | previews: previews, utterances: state.utterances ++ [event]}}
  end

  def handle_info({:jotty_session_event, %RealtimeTranscriptionFailed{} = failure}, state) do
    source = if failure.source == nil, do: "transport", else: Atom.to_string(failure.source)
    reason = inspect(failure.reason)
    event = %{type: :realtime_transcription_failed, source: failure.source, reason: reason}
    publish(state.client, event)
    {:noreply, %{state | realtime_error: "#{source}: #{reason}"}}
  end

  def handle_info({:recording_finished, worker, {:ok, recording}}, %{worker: worker} = state) do
    summary = File.read!(recording.summary)

    event = %{
      type: :summary_ready,
      markdown: summary,
      recording_directory: recording.directory
    }

    publish(state.client, event)

    state = %{
      state
      | status: :completed,
        summary: summary,
        recording_directory: recording.directory,
        worker: nil,
        worker_reference: nil
    }

    {:noreply, state}
  end

  def handle_info({:recording_finished, worker, {:error, reason}}, %{worker: worker} = state) do
    event = %{type: :failed, reason: inspect(reason)}
    publish(state.client, event)
    {:noreply, %{state | status: :failed, worker: nil, worker_reference: nil}}
  end

  def handle_info(
        {:DOWN, reference, :process, worker, reason},
        %{
          worker: worker,
          worker_reference: reference
        } = state
      ) do
    event = %{type: :failed, reason: inspect(reason)}
    publish(state.client, event)
    {:noreply, %{state | status: :failed, worker: nil, worker_reference: nil}}
  end

  def handle_info({:DOWN, _reference, :process, _worker, _reason}, state), do: {:noreply, state}

  defp snapshot(state) do
    %{
      type: :snapshot,
      status: state.status,
      utterances: state.utterances,
      previews: state.previews,
      realtime_error: state.realtime_error,
      summary: state.summary,
      recording_directory: state.recording_directory
    }
  end

  defp publish(nil, _event), do: :ok
  defp publish(client, event), do: send(client, {:jotty_desktop_event, event})
end
