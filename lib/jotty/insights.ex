defmodule Jotty.Insights do
  @moduledoc "Orchestrates insight classification and read-only project-context search."

  use GenServer

  require Logger

  alias Jotty.Insights.{IntentClassifier, Search}
  alias Jotty.Session.Events.HermesActivityObserved
  alias Jotty.Session.Events.UtteranceCompleted
  alias Jotty.STT.TranscriptionChunk

  @spec start(Path.t(), [Path.t()], (HermesActivityObserved.t() -> any())) :: GenServer.on_start()
  def start(recording_directory, context_directories, on_event \\ fn _event -> :ok end) do
    context_directories = Enum.map(context_directories, &Path.expand/1)

    with :ok <- validate_contexts(context_directories),
         {:ok, hermes} <- find_executable("hermes", :hermes_not_found) do
      output_path = Path.join(recording_directory, "insights.md")
      File.write!(output_path, "# Insights\n\n")

      state = %{
        context_directories: context_directories,
        hermes: hermes,
        history: [],
        on_event: on_event,
        output_path: output_path,
        result: :ok
      }

      GenServer.start(__MODULE__, {Logger.metadata(), state})
    end
  end

  @spec submit(pid(), UtteranceCompleted.t()) :: :ok
  def submit(insights, %UtteranceCompleted{} = event) do
    GenServer.cast(insights, {:submit, event})
  end

  @spec finish(pid()) :: {:ok, Path.t()} | {:error, term()}
  def finish(insights), do: GenServer.call(insights, :finish, :infinity)

  @spec disable(pid()) :: :ok
  def disable(insights), do: GenServer.cast(insights, :disable)

  @spec run(Path.t(), [Path.t()], Enumerable.t(), DateTime.t()) ::
          {:ok, Path.t()} | {:error, term()}
  def run(home, context_directories, utterances, started_at, on_event \\ fn _event -> :ok end) do
    context_directories = Enum.map(context_directories, &Path.expand/1)

    with :ok <- validate_contexts(context_directories),
         {:ok, hermes} <- find_executable("hermes", :hermes_not_found) do
      output_path = create_session!(home, started_at)

      case process_utterances(utterances, [], context_directories, output_path, hermes, on_event) do
        :ok -> {:ok, output_path}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl GenServer
  def init({metadata, state}) do
    Logger.metadata(metadata)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:submit, %UtteranceCompleted{chunks: chunks}}, %{result: :ok} = state) do
    utterance = Enum.map_join(chunks, fn %TranscriptionChunk{text: text} -> text end)

    result =
      process_utterance(
        utterance,
        state.history,
        state.context_directories,
        state.output_path,
        state.hermes,
        state.on_event
      )

    handle_utterance(result, state)
  end

  def handle_cast({:submit, %UtteranceCompleted{}}, state), do: {:noreply, state}
  def handle_cast(:disable, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_call(:finish, _from, %{result: :ok} = state) do
    {:stop, :normal, {:ok, state.output_path}, state}
  end

  def handle_call(:finish, _from, %{result: {:error, reason}} = state) do
    {:stop, :normal, {:error, reason}, state}
  end

  @spec validate_contexts([Path.t()]) :: :ok | {:error, {:context_directory_not_found, Path.t()}}
  def validate_contexts(context_directories) do
    case Enum.find(context_directories, &(not File.dir?(&1))) do
      nil -> :ok
      path -> {:error, {:context_directory_not_found, path}}
    end
  end

  defp find_executable(name, error) do
    case System.find_executable(name) do
      nil -> {:error, error}
      executable -> {:ok, executable}
    end
  end

  defp create_session!(home, started_at) do
    directory =
      Path.join([
        home,
        ".jotty",
        "sessions",
        Calendar.strftime(started_at, "%Y%m%d-%H%M%S")
      ])

    File.mkdir_p!(directory)
    output_path = Path.join(directory, "insights.md")
    File.write!(output_path, "# Insights\n\n")
    output_path
  end

  defp process_utterances(
         utterances,
         history,
         context_directories,
         output_path,
         hermes,
         on_event
       ) do
    result =
      Enum.reduce_while(utterances, {:ok, history}, fn line, {:ok, history} ->
        result = process_utterance(line, history, context_directories, output_path, hermes, on_event)
        reduce_utterance(result)
      end)

    case result do
      {:ok, _history} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_utterance(line, history, context_directories, output_path, hermes, on_event) do
    utterance = String.trim(line)

    if utterance == "" do
      {:ok, history}
    else
      history = Enum.take(history ++ [utterance], -5)
      working_directory = Path.dirname(output_path)
      decision = IntentClassifier.classify(hermes, history, working_directory, on_event)

      handle_decision(decision, utterance, history, context_directories, output_path, hermes, on_event)
    end
  end

  defp append_result!(output_path, utterance, query, markdown) do
    File.write!(
      output_path,
      "## #{query}\n\n**Trigger:** #{utterance}\n\n#{markdown}\n\n",
      ~w(append)a
    )
  end

  defp handle_utterance({:ok, history}, state) do
    {:noreply, %{state | history: history}}
  end

  defp handle_utterance({:error, reason}, state) do
    Logger.error("lookup_failed",
      scope: :insights,
      stage: failure_stage(reason),
      reason: inspect(reason)
    )

    {:noreply, %{state | result: {:error, reason}}}
  end

  defp failure_stage({stage, _reason}) when stage in ~w(insight_classification insight_search)a, do: stage

  defp reduce_utterance({:ok, history}), do: {:cont, {:ok, history}}
  defp reduce_utterance({:error, reason}), do: {:halt, {:error, reason}}

  defp handle_decision(:ignore, _utterance, history, _contexts, _output, _hermes, _on_event) do
    {:ok, history}
  end

  defp handle_decision(
         {:error, reason},
         _utterance,
         _history,
         _contexts,
         _output,
         _hermes,
         _on_event
       ) do
    {:error, reason}
  end

  defp handle_decision({:search, query}, utterance, history, contexts, output, hermes, on_event) do
    working_directory = Path.dirname(output)

    case Search.run(hermes, query, history, contexts, working_directory, on_event) do
      {:ok, markdown} ->
        append_result!(output, utterance, query, markdown)
        {:ok, history}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
