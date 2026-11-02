defmodule Jotty.Desktop.Controller do
  @moduledoc "Owns the active realtime session and durable desktop session catalog."

  use GenServer

  alias Jotty.Desktop.Commands.{
    ApproveTask,
    DeleteSession,
    DenyTask,
    ListSessions,
    OpenSession,
    RenameSession,
    StartSession,
    StopSession
  }

  alias Jotty.Desktop.Controller.ActiveSession
  alias Jotty.Desktop.Events.{CommandRejected, SessionDeleted, SessionOpened, SessionRenamed, SessionsListed}
  alias Jotty.Recording

  alias Jotty.Session.Events.{
    HermesActivityObserved,
    RecorderFinished,
    RecordingStarted,
    RealtimeTranscriptionFailed,
    SessionCompleted,
    SessionFailed,
    SessionStarting,
    SessionStopping,
    SummaryReady,
    TaskAnalysisFailed,
    TaskCardProposed,
    TaskCardUpdated,
    TaskSearchStarted,
    TranscriptionPreviewed,
    UtteranceCompleted
  }

  alias Jotty.Session.Server, as: SessionServer
  alias Jotty.Sessions.{Catalog, Recordings, Session}
  alias Jotty.{Recorder, Settings}

  @type state :: %{
          client: pid() | nil,
          active: ActiveSession.t() | nil,
          selected_session_id: Ecto.UUID.t() | nil,
          home: Path.t(),
          recorder: Path.t(),
          session_options: keyword(),
          audio_base_url: String.t()
        }

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def attach(controller, client), do: GenServer.call(controller, {:attach, client})
  def command(controller, command), do: GenServer.call(controller, {:command, command})
  def active_session_id(controller), do: GenServer.call(controller, :active_session_id)

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)
    :ok = Recordings.fail_orphaned(DateTime.utc_now())

    {:ok,
     %{
       client: nil,
       active: nil,
       selected_session_id: nil,
       home: Keyword.get(options, :home, System.user_home!()),
       recorder: Keyword.fetch!(options, :recorder),
       session_options: Keyword.fetch!(options, :session_options),
       audio_base_url: Keyword.fetch!(options, :audio_base_url)
     }}
  end

  @impl GenServer
  def handle_call({:attach, client}, _from, state) do
    state = %{state | client: client}

    case attachment_snapshot(state) do
      {:ok, snapshot} ->
        {:reply, snapshot, replay_selection(state)}

      {:error, reason} ->
        state = fail_active(state, {:session_process_exit, reason})
        {:reply, idle_snapshot(), state}
    end
  end

  def handle_call(:active_session_id, _from, state) do
    {:reply, state.active && state.active.id, state}
  end

  def handle_call({:command, %StartSession{}}, _from, %{active: nil} = state) do
    case start_session(state) do
      {:ok, state} -> {:reply, :ok, %{state | selected_session_id: nil}}
      {:error, reason, state} -> {:reply, {:event, rejected(:start_session, reason)}, state}
    end
  end

  def handle_call({:command, %StartSession{}}, _from, state) do
    {:reply, {:event, rejected(:start_session, :session_already_active)}, state}
  end

  def handle_call({:command, %StopSession{}}, _from, %{active: %{pid: pid, phase: :recording}} = state) do
    case session_call(fn -> SessionServer.stop_recording(pid) end) do
      {:ok, :ok} ->
        {:reply, :ok, state}

      {:error, reason} ->
        state = fail_active(state, {:session_process_exit, reason})
        {:reply, {:event, rejected(:stop_session, {:session_process_exit, reason})}, state}
    end
  end

  def handle_call({:command, %StopSession{}}, _from, %{active: active} = state) when active != nil do
    {:reply, {:event, rejected(:stop_session, {:invalid_phase, active.phase})}, state}
  end

  def handle_call({:command, %StopSession{}}, _from, state) do
    {:reply, {:event, rejected(:stop_session, :no_active_session)}, state}
  end

  def handle_call({:command, %ApproveTask{card_id: card_id}}, _from, %{active: %{pid: pid}} = state) do
    task_command(:approve_task, fn -> SessionServer.approve_task(pid, card_id) end, state)
  end

  def handle_call({:command, %DenyTask{card_id: card_id}}, _from, %{active: %{pid: pid}} = state) do
    task_command(:deny_task, fn -> SessionServer.deny_task(pid, card_id) end, state)
  end

  def handle_call({:command, %ApproveTask{}}, _from, state) do
    {:reply, {:event, rejected(:approve_task, :no_active_session)}, state}
  end

  def handle_call({:command, %DenyTask{}}, _from, state) do
    {:reply, {:event, rejected(:deny_task, :no_active_session)}, state}
  end

  def handle_call({:command, %command_struct{} = command}, _from, %{active: active} = state)
      when active != nil and command_struct in [ListSessions, OpenSession, RenameSession, DeleteSession] do
    {:reply, {:event, rejected(command_name(command), :session_active)}, state}
  end

  def handle_call({:command, %ListSessions{}}, _from, state) do
    {:reply, {:event, %SessionsListed{sessions: Catalog.all()}}, state}
  end

  def handle_call({:command, %OpenSession{id: id}}, _from, state) do
    case Catalog.open(id, state.audio_base_url) do
      {:ok, session} ->
        {:reply, {:event, %SessionOpened{session: session}}, %{state | selected_session_id: session.id}}

      {:error, reason} ->
        {:reply, {:event, rejected(:open_session, reason)}, state}
    end
  end

  def handle_call({:command, %RenameSession{id: id, title: title}}, _from, state) do
    event =
      case Catalog.rename(id, title) do
        {:ok, session} -> %SessionRenamed{session: session}
        {:error, reason} -> rejected(:rename_session, reason)
      end

    {:reply, {:event, event}, state}
  end

  def handle_call({:command, %DeleteSession{id: id}}, _from, state) do
    root = Path.join([state.home, ".jotty", "recordings"])

    event =
      case Catalog.delete(id, root) do
        :ok -> %SessionDeleted{id: id}
        {:error, reason} -> rejected(:delete_session, reason)
      end

    state =
      if match?(%SessionDeleted{}, event) and state.selected_session_id == id,
        do: %{state | selected_session_id: nil},
        else: state

    {:reply, {:event, event}, state}
  end

  @impl GenServer
  def handle_info({:jotty_session_event, event}, state) do
    state = forward_session_event(state, event)
    {:noreply, handle_session_event(event, state)}
  end

  def handle_info({:EXIT, pid, reason}, %{active: %{pid: pid} = active} = state) do
    reason = {:session_process_exit, reason}
    fail_recording!(active, reason)

    state =
      state
      |> emit(%SessionFailed{reason: reason})
      |> open_completed(active.id)

    {:noreply, %{state | active: nil}}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(reason, %{active: %{pid: pid} = active}) when is_pid(pid) do
    fail_recording!(active, {:controller_shutdown, reason})
    GenServer.stop(pid)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_session(state) do
    with {:ok, microphones} <- Recorder.list_microphones(state.recorder),
         settings <- Settings.snapshot(microphones),
         {:ok, configuration} <- Settings.recording_configuration(settings) do
      started_at = DateTime.utc_now()
      id = Ecto.UUID.generate()
      recording = Recording.create!(state.home, started_at, id)
      Recordings.create!(recording, started_at, settings.contexts)

      options =
        Keyword.merge(state.session_options,
          recorder: state.recorder,
          recorder_options: [stop: :message],
          recording: recording,
          event_sinks: [self()]
        )

      case SessionServer.start_link(options) do
        {:ok, pid} ->
          active = %ActiveSession{pid: pid, id: id, recording: recording, phase: :starting, chunks: []}
          :ok = SessionServer.start_recording(pid, configuration)
          {:ok, %{state | active: active}}

        {:error, reason} ->
          {:ok, %Session{}} = Recordings.fail(id, [], DateTime.utc_now(), reason)
          {:error, reason, state}
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp handle_session_event(%SessionStarting{}, %{active: active} = state) do
    %{state | active: %{active | phase: :starting}}
  end

  defp handle_session_event(%RecordingStarted{}, %{active: active} = state) do
    %{state | active: %{active | phase: :recording}}
  end

  defp handle_session_event(%SessionStopping{}, %{active: active} = state) do
    %{state | active: %{active | phase: :stopping}}
  end

  defp handle_session_event(%UtteranceCompleted{chunks: chunks}, %{active: active} = state) do
    %{state | active: %{active | chunks: active.chunks ++ chunks}}
  end

  defp handle_session_event(%SessionCompleted{}, %{active: active} = state) do
    case Recordings.complete(active.id, active.chunks, DateTime.utc_now()) do
      {:ok, _session} ->
        active = %{active | phase: :completed}
        maybe_finalize_completed(%{state | active: active})

      {:error, reason} ->
        fail_recording!(active, {:catalog, reason})

        state
        |> emit(%SessionFailed{reason: {:catalog, reason}})
        |> reap_active()
    end
  end

  defp handle_session_event(%SessionFailed{reason: reason}, %{active: active} = state) do
    fail_recording!(active, reason)
    active = %{active | phase: {:failed, reason}}
    state = %{state | active: active}
    if SessionServer.reap_ready?(active.pid), do: finalize_failed(state), else: state
  end

  defp handle_session_event(%RecorderFinished{}, %{active: %{phase: {:failed, _}}} = state) do
    finalize_failed(state)
  end

  defp handle_session_event(%event{}, %{active: %{phase: :completed}} = state)
       when event in [TaskCardProposed, TaskCardUpdated, TaskAnalysisFailed] do
    maybe_finalize_completed(state)
  end

  defp handle_session_event(_event, state), do: state

  defp open_completed(state, id) do
    case Catalog.open(id, state.audio_base_url) do
      {:ok, session} ->
        state
        |> Map.put(:selected_session_id, id)
        |> emit(%SessionOpened{session: session})

      {:error, _reason} ->
        state
    end
  end

  defp finalize_failed(%{active: %{id: id}} = state) do
    state
    |> open_completed(id)
    |> reap_active()
  end

  defp maybe_finalize_completed(%{active: %{pid: pid, id: id}} = state) do
    case session_call(fn -> SessionServer.snapshot(pid) end) do
      {:ok, snapshot} ->
        waiting? =
          snapshot.task_search_query != nil or
            Enum.any?(snapshot.task_cards, &(&1.status in [:pending, :applying]))

        if waiting?, do: state, else: state |> open_completed(id) |> reap_active()

      {:error, reason} ->
        fail_active(state, {:session_process_exit, reason})
    end
  end

  defp reap_active(%{active: %{pid: pid}} = state) do
    GenServer.stop(pid)
    %{state | active: nil}
  end

  defp forward_session_event(state, %SessionStarting{}), do: emit(state, %{type: :state, status: :starting})
  defp forward_session_event(state, %RecordingStarted{}), do: emit(state, %{type: :state, status: :recording})
  defp forward_session_event(state, %SessionStopping{}), do: emit(state, %{type: :state, status: :stopping})
  defp forward_session_event(state, %SessionCompleted{}), do: emit(state, %{type: :state, status: :completed})
  defp forward_session_event(state, %TranscriptionPreviewed{} = event), do: emit(state, event)
  defp forward_session_event(state, %UtteranceCompleted{} = event), do: emit(state, event)

  defp forward_session_event(state, %TaskCardProposed{card: card}) do
    emit(state, %{type: :task_card_proposed, card: card})
  end

  defp forward_session_event(state, %TaskCardUpdated{card: card}) do
    emit(state, %{type: :task_card_updated, card: card})
  end

  defp forward_session_event(state, %TaskSearchStarted{query: query}) do
    emit(state, %{type: :task_search_started, query: query})
  end

  defp forward_session_event(state, %TaskAnalysisFailed{reason: reason}) do
    emit(state, %{type: :task_analysis_failed, reason: inspect(reason)})
  end

  defp forward_session_event(state, %HermesActivityObserved{} = event) do
    emit(state, %{
      type: :hermes_activity,
      stage: event.stage,
      status: event.status,
      message: event.message
    })
  end

  defp forward_session_event(state, %RealtimeTranscriptionFailed{} = event) do
    emit(state, %{type: :realtime_transcription_failed, source: event.source, reason: inspect(event.reason)})
  end

  defp forward_session_event(state, %SummaryReady{} = event) do
    emit(state, %{
      type: :summary_ready,
      markdown: event.markdown,
      recording_directory: event.recording.directory
    })
  end

  defp forward_session_event(state, %SessionFailed{} = event) do
    emit(state, %{type: :failed, reason: inspect(event.reason)})
  end

  defp forward_session_event(state, _event), do: state

  defp emit(%{client: nil} = state, _event), do: state

  defp emit(%{client: client} = state, event) do
    send(client, {:jotty_desktop_event, event})
    state
  end

  defp attachment_snapshot(%{active: nil}), do: {:ok, idle_snapshot()}

  defp attachment_snapshot(%{active: %{pid: pid}}) do
    case session_call(fn -> SessionServer.snapshot(pid) end) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay_selection(%{selected_session_id: nil} = state), do: state

  defp replay_selection(%{selected_session_id: id} = state) do
    case Catalog.open(id, state.audio_base_url) do
      {:ok, session} -> emit(state, %SessionOpened{session: session})
      {:error, _reason} -> %{state | selected_session_id: nil}
    end
  end

  defp idle_snapshot do
    %{
      type: :snapshot,
      status: :idle,
      utterances: [],
      preview: nil,
      realtime_error: nil,
      summary: nil,
      activities: [],
      task_cards: [],
      task_search_query: nil,
      task_error: nil
    }
  end

  defp task_command(command, callback, state) do
    case session_call(callback) do
      {:ok, :ok} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:event, rejected(command, {:session_process_exit, reason})}, state}
    end
  end

  defp session_call(function) do
    {:ok, function.()}
  catch
    :exit, reason -> {:error, reason}
  end

  defp fail_active(%{active: active} = state, reason) do
    fail_recording!(active, reason)

    state
    |> Map.put(:active, nil)
    |> emit(%SessionFailed{reason: reason})
    |> open_completed(active.id)
  end

  defp rejected(command, reason), do: %CommandRejected{command: command, reason: format_reason(reason)}
  defp format_reason(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp format_reason(reason), do: inspect(reason)

  defp command_name(%ListSessions{}), do: :list_sessions
  defp command_name(%OpenSession{}), do: :open_session
  defp command_name(%RenameSession{}), do: :rename_session
  defp command_name(%DeleteSession{}), do: :delete_session

  defp fail_recording!(active, reason) do
    {:ok, %Session{} = session} = Recordings.fail(active.id, active.chunks, DateTime.utc_now(), reason)
    session
  end
end
