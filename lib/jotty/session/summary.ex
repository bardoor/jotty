defmodule Jotty.Session.Summary do
  @moduledoc "Creates the summary after the canonical transcript is ready."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Session.Events

  alias Jotty.Session.Events.{
    ProcessExited,
    SessionTerminating,
    SummaryCompleted,
    SummaryFailed,
    SummaryReady,
    TranscriptReady
  }

  alias Jotty.Session.{Recording, Server, State}

  @type t :: %__MODULE__{
          summarizer: module(),
          worker: pid() | nil,
          reference: reference() | nil
        }

  @enforce_keys [:summarizer]
  defstruct [:summarizer, worker: nil, reference: nil]

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{summarizer: Keyword.get(options, :summarizer, Jotty.Summarizer)}
  end

  @impl true
  def subscriptions, do: [TranscriptReady, SummaryCompleted, ProcessExited, SessionTerminating]

  @impl true
  def handle_message(%TranscriptReady{}, %State{recording: %Recording{result: :ok}} = state) do
    Logger.info("starting", scope: :summary)
    recording = state.recording.recording
    server = self()

    {worker, reference} =
      Jotty.Process.spawn_monitor(fn ->
        result = state.summary.summarizer.summarize(recording.transcript, recording.summary)
        Server.publish(server, %SummaryCompleted{result: result})
      end)

    %{state | summary: %{state.summary | worker: worker, reference: reference}}
  end

  def handle_message(%TranscriptReady{}, %State{} = state), do: state

  def handle_message(%SummaryCompleted{result: :ok}, %State{} = state) do
    Logger.info("ready", scope: :summary)
    recording = state.recording.recording
    state = clear_worker(state)
    markdown = File.read!(recording.summary)
    Events.publish(state, %SummaryReady{recording: recording, markdown: markdown})
  end

  def handle_message(%SummaryCompleted{result: {:error, reason}}, %State{} = state) do
    Logger.error("failed", scope: :summary, reason: inspect(reason))

    state
    |> clear_worker()
    |> Events.publish(%SummaryFailed{reason: reason})
  end

  def handle_message(
        %ProcessExited{reference: reference, pid: worker, reason: reason},
        %State{summary: %__MODULE__{reference: reference, worker: worker}} = state
      ) do
    Logger.error("failed", scope: :summary, reason: inspect({:summary_process_exit, reason}))

    state
    |> clear_worker()
    |> Events.publish(%SummaryFailed{reason: {:summary_process_exit, reason}})
  end

  def handle_message(%ProcessExited{}, %State{} = state), do: state

  def handle_message(%SessionTerminating{}, %State{summary: %__MODULE__{worker: worker}} = state)
      when is_pid(worker) do
    Process.exit(worker, :kill)
    state
  end

  def handle_message(%SessionTerminating{}, %State{} = state), do: state

  defp clear_worker(state) do
    %{state | summary: %{state.summary | worker: nil, reference: nil}}
  end
end
