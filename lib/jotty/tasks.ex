defmodule Jotty.Tasks do
  @moduledoc "Analyzes completed utterances and prepares approval-gated Linear task cards."

  use GenServer

  require Logger

  alias Jotty.Session.Events.{
    TaskAnalysisFailed,
    TaskCardProposed,
    TaskCardUpdated,
    TaskSearchStarted,
    UtteranceCompleted
  }

  alias Jotty.STT.TranscriptionChunk
  alias Jotty.Tasks.{Card, Executor, IntentClassifier, Proposer, Store}

  @type option ::
          {:recording_directory, Path.t()}
          | {:hermes, Path.t()}
          | {:classifier, module()}
          | {:proposer, module()}
          | {:executor, module()}
          | {:on_event, (struct() -> any())}
          | {:metadata, keyword()}

  @spec start([option()]) :: GenServer.on_start()
  def start(options) do
    recording_directory = Keyword.fetch!(options, :recording_directory)
    hermes = Keyword.get_lazy(options, :hermes, &find_hermes!/0)
    output_path = Path.join(recording_directory, "tasks.json")
    {:ok, cards} = Store.read(output_path)

    state = %{
      hermes: hermes,
      history: [],
      cards: cards,
      output_path: output_path,
      classifier: Keyword.get(options, :classifier, IntentClassifier),
      proposer: Keyword.get(options, :proposer, Proposer),
      executor: Keyword.get(options, :executor, Executor),
      on_event: Keyword.get(options, :on_event, fn _event -> :ok end),
      metadata: Keyword.get(options, :metadata, Logger.metadata())
    }

    with :ok <- Store.write(output_path, cards) do
      GenServer.start(__MODULE__, state)
    end
  end

  @spec submit(pid(), UtteranceCompleted.t()) :: :ok
  def submit(tasks, %UtteranceCompleted{} = event), do: GenServer.cast(tasks, {:submit, event})

  @spec approve(pid(), Card.t()) :: :ok
  def approve(tasks, %Card{} = card), do: GenServer.cast(tasks, {:approve, card})

  @spec deny(pid(), Card.t()) :: :ok
  def deny(tasks, %Card{} = card), do: GenServer.cast(tasks, {:deny, card})

  @spec flush(pid()) :: :ok
  def flush(tasks), do: GenServer.call(tasks, :flush, :infinity)

  @spec finish(pid()) :: {:ok, Path.t()}
  def finish(tasks), do: GenServer.call(tasks, :finish, :infinity)

  @spec disable(pid()) :: :ok
  def disable(tasks), do: GenServer.cast(tasks, :disable)

  @impl GenServer
  def init(state) do
    Logger.metadata(state.metadata)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:submit, %UtteranceCompleted{chunks: chunks}}, state) do
    utterance = Enum.map_join(chunks, fn %TranscriptionChunk{text: text} -> text end)
    history = Enum.take(state.history ++ [utterance], -5)
    working_directory = Path.dirname(state.output_path)

    result = state.classifier.classify(state.hermes, history, state.cards, working_directory, state.on_event)
    state = handle_classification(result, history, state, working_directory)
    {:noreply, %{state | history: history}}
  end

  def handle_cast({:approve, %Card{} = card}, state) do
    working_directory = Path.dirname(state.output_path)
    state = persist_card(%{card | status: :applying}, state)

    case state.executor.apply(state.hermes, card, working_directory, state.on_event) do
      {:ok, %Card{} = applied} -> update_card(applied, state)
      {:error, reason} -> update_card(%{card | status: :failed, error: inspect(reason)}, state)
    end
  end

  def handle_cast({:deny, %Card{} = card}, state) do
    update_card(%{card | status: :denied}, state)
  end

  def handle_cast(:disable, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_call(:flush, _from, state), do: {:reply, :ok, state}

  def handle_call(:finish, _from, state) do
    {:stop, :normal, {:ok, state.output_path}, state}
  end

  defp handle_classification(:ignore, _history, state, _working_directory), do: state

  defp handle_classification({:inspect_linear, query}, history, state, working_directory) do
    state.on_event.(%TaskSearchStarted{query: query})

    case state.proposer.propose(state.hermes, query, history, working_directory, state.on_event) do
      {:ok, %Card{} = card} -> propose_card(card, state)
      {:error, reason} -> analysis_failed(reason, state)
    end
  end

  defp handle_classification({:error, reason}, _history, state, _working_directory) do
    analysis_failed(reason, state)
  end

  defp propose_card(card, state) do
    cards = state.cards ++ [card]
    :ok = Store.write(state.output_path, cards)
    state.on_event.(%TaskCardProposed{card: card})
    %{state | cards: cards}
  end

  defp update_card(card, state) do
    {:noreply, persist_card(card, state)}
  end

  defp persist_card(card, state) do
    cards = Enum.map(state.cards, fn existing -> if existing.id == card.id, do: card, else: existing end)
    :ok = Store.write(state.output_path, cards)
    state.on_event.(%TaskCardUpdated{card: card})
    %{state | cards: cards}
  end

  defp analysis_failed(reason, state) do
    Logger.error("analysis_failed", scope: :tasks, reason: inspect(reason))
    state.on_event.(%TaskAnalysisFailed{reason: reason})
    state
  end

  defp find_hermes! do
    System.find_executable("hermes") || raise "hermes executable was not found in PATH"
  end
end
