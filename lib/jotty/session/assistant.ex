defmodule Jotty.Session.Assistant do
  @moduledoc "Connects completed utterance events to the optional context assistant."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Assistant, as: AssistantWorker
  alias Jotty.Session.Events

  alias Jotty.Session.Events.{
    RealtimeTranscriptionFailed,
    SessionFailed,
    SessionStarting,
    SessionTerminating,
    TranscriptionFinished,
    UtteranceCompleted
  }

  alias Jotty.Session.State

  @type t :: %__MODULE__{contexts: [Path.t()], pid: pid() | nil}

  defstruct contexts: [], pid: nil

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{contexts: Keyword.get(options, :contexts, [])}
  end

  @impl true
  def subscriptions do
    [
      SessionStarting,
      UtteranceCompleted,
      TranscriptionFinished,
      RealtimeTranscriptionFailed,
      SessionFailed,
      SessionTerminating
    ]
  end

  @impl true
  def handle_message(%SessionStarting{}, %State{} = state) do
    case start(state) do
      {:ok, state} -> state
      {:error, reason, state} -> Events.publish(state, %SessionFailed{reason: reason})
    end
  end

  def handle_message(_message, %State{assistant: %__MODULE__{pid: nil}} = state), do: state

  def handle_message(%UtteranceCompleted{} = event, %State{assistant: %__MODULE__{pid: pid}} = state) do
    AssistantWorker.submit(pid, event)
    state
  end

  def handle_message(%TranscriptionFinished{}, %State{assistant: %__MODULE__{pid: pid}} = state) do
    Logger.info("finished", scope: :assistant)
    AssistantWorker.finish(pid)
    %{state | assistant: %{state.assistant | pid: nil}}
  end

  def handle_message(%RealtimeTranscriptionFailed{}, %State{assistant: %__MODULE__{pid: pid}} = state) do
    AssistantWorker.disable(pid)
    %{state | assistant: %{state.assistant | pid: nil}}
  end

  def handle_message(%SessionFailed{}, %State{assistant: %__MODULE__{pid: pid}} = state) do
    AssistantWorker.disable(pid)
    %{state | assistant: %{state.assistant | pid: nil}}
  end

  def handle_message(%SessionTerminating{}, %State{assistant: %__MODULE__{pid: pid}} = state) do
    AssistantWorker.disable(pid)
    state
  end

  defp start(%State{assistant: %__MODULE__{contexts: []}} = state), do: {:ok, state}

  defp start(%State{} = state) do
    Logger.info("starting", scope: :assistant, context_count: length(state.assistant.contexts))

    case AssistantWorker.start(state.recording.recording.directory, state.assistant.contexts) do
      {:ok, pid} ->
        Logger.info("started", scope: :assistant)
        {:ok, %{state | assistant: %{state.assistant | pid: pid}}}

      {:error, reason} ->
        Logger.error("failed", scope: :assistant, reason: inspect(reason))
        {:error, reason, state}
    end
  end
end
