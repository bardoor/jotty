defmodule Jotty.Session.Recording do
  @moduledoc "Owns the native recorder worker and its lifecycle state."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Recorder
  alias Jotty.Recording, as: RecordingArtifact
  alias Jotty.Session.Events

  alias Jotty.Session.Events.{
    ProcessExited,
    RecorderFinished,
    RecordingStarted,
    SessionFailed,
    SessionStarting,
    SessionStopping,
    SessionTerminating
  }

  alias Jotty.Session.Events.RecorderReady
  alias Jotty.Session.{Server, State}

  @type phase :: :idle | :starting | :recording | :stopping | :finished
  @type recording_source :: RecordingArtifact.t() | (-> RecordingArtifact.t())
  @type t :: %__MODULE__{
          executable: Path.t(),
          recording: recording_source(),
          options: keyword(),
          worker: pid() | nil,
          reference: reference() | nil,
          result: Jotty.Recorder.result() | nil,
          phase: phase()
        }

  @enforce_keys [:executable, :recording]
  defstruct [:executable, :recording, options: [], worker: nil, reference: nil, result: nil, phase: :idle]

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{
      executable: Keyword.fetch!(options, :recorder),
      recording: Keyword.fetch!(options, :recording),
      options: Keyword.get(options, :recorder_options, [])
    }
  end

  @impl true
  def subscriptions do
    [
      SessionStarting,
      SessionStopping,
      RecorderReady,
      RecorderFinished,
      ProcessExited,
      SessionFailed,
      SessionTerminating
    ]
  end

  @impl true
  def handle_message(%SessionStarting{}, %State{} = state), do: start(state)

  def handle_message(%SessionStopping{}, %State{} = state) do
    Logger.info("stopping", scope: :recording, reason: inspect(:requested))
    stop(state)
  end

  def handle_message(%RecorderReady{}, %State{recording: %__MODULE__{phase: :starting}} = state) do
    Logger.info("ready", scope: :recording)
    recording = %{state.recording | phase: :recording}

    state = %{state | recording: recording}
    Events.publish(state, %RecordingStarted{})
  end

  def handle_message(%RecorderReady{}, %State{} = state), do: state

  def handle_message(%RecorderFinished{result: result}, %State{} = state) do
    log_result(result)
    recording = %{state.recording | worker: nil, reference: nil, result: result, phase: :finished}
    %{state | recording: recording}
  end

  def handle_message(
        %ProcessExited{reference: reference, pid: worker, reason: reason},
        %State{recording: %__MODULE__{reference: reference, worker: worker, result: nil}} = state
      ) do
    Events.publish(state, %RecorderFinished{result: {:error, {:recorder_process_exit, reason}}})
  end

  def handle_message(%ProcessExited{}, %State{} = state), do: state

  def handle_message(%SessionFailed{}, %State{recording: %__MODULE__{worker: worker}} = state)
      when is_pid(worker) do
    Logger.info("stopping", scope: :recording, reason: inspect(:session_failed))
    stop(state)
  end

  def handle_message(%SessionFailed{}, %State{} = state), do: state

  def handle_message(%SessionTerminating{}, %State{recording: %__MODULE__{worker: worker}} = state)
      when is_pid(worker) do
    Logger.info("stopping", scope: :recording, reason: inspect(:session_terminating))
    stop(state)
  end

  def handle_message(%SessionTerminating{}, %State{} = state), do: state

  defp start(%State{} = state) do
    recording = recording(state.recording.recording)
    Logger.metadata(recording_id: Path.basename(recording.directory))
    Logger.info("starting", scope: :recording)
    server = self()
    executable = state.recording.executable
    recorder_options = Keyword.put(state.recording.options, :stop, :message)

    {worker, reference} =
      Jotty.Process.spawn_monitor(fn ->
        result =
          Recorder.record_live(executable, recording.directory, &publish_frame(server, &1), recorder_options)

        Server.publish(server, %RecorderFinished{result: result})
      end)

    recording_state = %{
      state.recording
      | recording: recording,
        worker: worker,
        reference: reference,
        phase: :starting
    }

    %{state | recording: recording_state}
  end

  defp stop(%State{recording: %__MODULE__{worker: worker}} = state) when is_pid(worker) do
    send(worker, :stop)
    %{state | recording: %{state.recording | phase: :stopping}}
  end

  defp stop(%State{} = state), do: state

  defp log_result(:ok), do: Logger.info("finished", scope: :recording)
  defp log_result({:error, reason}), do: Logger.error("failed", scope: :recording, reason: inspect(reason))

  defp recording(recording) when is_function(recording, 0), do: recording(recording.())
  defp recording(%RecordingArtifact{} = recording), do: recording

  defp publish_frame(server, :ready), do: Server.publish(server, %RecorderReady{})

  defp publish_frame(server, {:pcm, pcm}) do
    Server.publish(server, %Events.AudioReceived{pcm: pcm})
  end

  defp publish_frame(server, {:live_source_failed, source, reason}) do
    Server.publish(server, %Events.NativeAudioFailed{source: source, reason: {:native, reason}})
  end

  defp publish_frame(server, {:live_transport_failed, reason}) do
    Server.publish(server, %Events.NativeAudioFailed{source: nil, reason: {:native_transport, reason}})
  end
end
