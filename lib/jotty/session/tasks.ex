defmodule Jotty.Session.Tasks do
  @moduledoc "Owns task analyzer lifecycle and immutable approval-card state."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Session.Events

  alias Jotty.Session.Events.{
    ApproveTaskRequested,
    DenyTaskRequested,
    RealtimeTranscriptionFailed,
    SessionFailed,
    SessionStarting,
    SessionTerminating,
    TaskAnalysisFailed,
    TaskCardProposed,
    TaskCardUpdated,
    TranscriptionFinished,
    UtteranceCompleted
  }

  alias Jotty.Session.{Server, State}
  alias Jotty.Tasks, as: TasksWorker
  alias Jotty.Tasks.{Card, Store}

  @type t :: %__MODULE__{
          worker_module: module(),
          pid: pid() | nil,
          cards: [Card.t()],
          error: String.t() | nil
        }

  @enforce_keys ~w(worker_module)a
  defstruct worker_module: nil, pid: nil, cards: [], error: nil

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{worker_module: Keyword.get(options, :tasks_worker, TasksWorker)}
  end

  @impl true
  def subscriptions do
    [
      SessionStarting,
      UtteranceCompleted,
      ApproveTaskRequested,
      DenyTaskRequested,
      TaskCardProposed,
      TaskCardUpdated,
      TaskAnalysisFailed,
      TranscriptionFinished,
      RealtimeTranscriptionFailed,
      SessionFailed,
      SessionTerminating
    ]
  end

  @impl true
  def handle_message(%SessionStarting{}, %State{} = state), do: start(state)

  def handle_message(%UtteranceCompleted{} = event, %State{tasks: %__MODULE__{pid: pid}} = state)
      when is_pid(pid) do
    state.tasks.worker_module.submit(pid, event)
    state
  end

  def handle_message(%ApproveTaskRequested{card_id: card_id}, %State{} = state) do
    with %Card{status: :pending} = card <- find_card(state.tasks.cards, card_id),
         pid when is_pid(pid) <- state.tasks.pid do
      applying = %{card | status: :applying}
      state.tasks.worker_module.approve(pid, card)
      Events.publish(state, %TaskCardUpdated{card: applying})
    else
      _not_pending -> state
    end
  end

  def handle_message(%DenyTaskRequested{card_id: card_id}, %State{} = state) do
    with %Card{status: :pending} = card <- find_card(state.tasks.cards, card_id),
         pid when is_pid(pid) <- state.tasks.pid do
      state.tasks.worker_module.deny(pid, card)
      state
    else
      _not_pending -> state
    end
  end

  def handle_message(%TaskCardProposed{card: card}, %State{} = state) do
    %{state | tasks: %{state.tasks | cards: state.tasks.cards ++ [card]}}
  end

  def handle_message(%TaskCardUpdated{card: card}, %State{} = state) do
    cards = Enum.map(state.tasks.cards, fn existing -> if existing.id == card.id, do: card, else: existing end)
    %{state | tasks: %{state.tasks | cards: cards}}
  end

  def handle_message(%TaskAnalysisFailed{reason: reason}, %State{} = state) do
    %{state | tasks: %{state.tasks | error: inspect(reason)}}
  end

  def handle_message(%TranscriptionFinished{}, %State{tasks: %__MODULE__{pid: pid}} = state)
      when is_pid(pid) do
    :ok = state.tasks.worker_module.flush(pid)
    state
  end

  def handle_message(%RealtimeTranscriptionFailed{}, %State{} = state), do: disable(state)
  def handle_message(%SessionFailed{}, %State{} = state), do: disable(state)
  def handle_message(%SessionTerminating{}, %State{} = state), do: disable(state)

  def handle_message(_message, %State{} = state), do: state

  defp disable(%State{tasks: %__MODULE__{pid: pid}} = state) when is_pid(pid) do
    state.tasks.worker_module.disable(pid)
    %{state | tasks: %{state.tasks | pid: nil}}
  end

  defp disable(%State{} = state), do: state

  defp start(%State{} = state) do
    server = self()
    directory = state.recording.recording.directory
    options = [recording_directory: directory, on_event: &Server.publish(server, &1)]

    case state.tasks.worker_module.start(options) do
      {:ok, pid} ->
        {:ok, cards} = Store.read(Path.join(directory, "tasks.json"))
        %{state | tasks: %{state.tasks | pid: pid, cards: cards, error: nil}}

      {:error, reason} ->
        Logger.error("unavailable", scope: :tasks, reason: inspect(reason))
        Events.publish(state, %TaskAnalysisFailed{reason: reason})
    end
  end

  defp find_card(cards, card_id), do: Enum.find(cards, &(&1.id == card_id))
end
