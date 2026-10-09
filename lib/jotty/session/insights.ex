defmodule Jotty.Session.Insights do
  @moduledoc "Connects completed utterances to optional insight classification and search."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Insights, as: InsightsWorker
  alias Jotty.Session.Events

  alias Jotty.Session.Events.{
    RealtimeTranscriptionFailed,
    SessionFailed,
    SessionStarting,
    SessionTerminating,
    StartSession,
    TranscriptionFinished,
    UtteranceCompleted
  }

  alias Jotty.Session.{Server, State}

  @type t :: %__MODULE__{contexts: [Path.t()], pid: pid() | nil}

  defstruct contexts: [], pid: nil

  @impl true
  def subscriptions do
    [
      SessionStarting,
      StartSession,
      UtteranceCompleted,
      TranscriptionFinished,
      RealtimeTranscriptionFailed,
      SessionFailed,
      SessionTerminating
    ]
  end

  @impl true
  def handle_message(%StartSession{contexts: contexts}, %State{} = state) do
    %{state | insights: %{state.insights | contexts: contexts}}
  end

  def handle_message(%SessionStarting{}, %State{} = state) do
    case start(state) do
      {:ok, state} -> state
      {:error, reason, state} -> Events.publish(state, %SessionFailed{reason: reason})
    end
  end

  def handle_message(_message, %State{insights: %__MODULE__{pid: nil}} = state), do: state

  def handle_message(%UtteranceCompleted{} = event, %State{insights: %__MODULE__{pid: pid}} = state) do
    InsightsWorker.submit(pid, event)
    state
  end

  def handle_message(%TranscriptionFinished{}, %State{insights: %__MODULE__{pid: pid}} = state) do
    Logger.info("finished", scope: :insights)
    InsightsWorker.finish(pid)
    %{state | insights: %{state.insights | pid: nil}}
  end

  def handle_message(%RealtimeTranscriptionFailed{}, %State{insights: %__MODULE__{pid: pid}} = state) do
    InsightsWorker.disable(pid)
    %{state | insights: %{state.insights | pid: nil}}
  end

  def handle_message(%SessionFailed{}, %State{insights: %__MODULE__{pid: pid}} = state) do
    InsightsWorker.disable(pid)
    %{state | insights: %{state.insights | pid: nil}}
  end

  def handle_message(%SessionTerminating{}, %State{insights: %__MODULE__{pid: pid}} = state) do
    InsightsWorker.disable(pid)
    state
  end

  defp start(%State{insights: %__MODULE__{contexts: []}} = state), do: {:ok, state}

  defp start(%State{} = state) do
    Logger.info("starting", scope: :insights, context_count: length(state.insights.contexts))
    server = self()
    on_event = &Server.publish(server, &1)

    case InsightsWorker.start(state.recording.recording.directory, state.insights.contexts, on_event) do
      {:ok, pid} ->
        Logger.info("started", scope: :insights)
        {:ok, %{state | insights: %{state.insights | pid: pid}}}

      {:error, reason} ->
        Logger.error("failed", scope: :insights, reason: inspect(reason))
        {:error, reason, state}
    end
  end
end
