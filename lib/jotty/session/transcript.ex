defmodule Jotty.Session.Transcript do
  @moduledoc "Owns canonical transcript accumulation and persistence."

  @behaviour Jotty.Session.Consumer

  require Logger

  alias Jotty.Session.Events
  alias Jotty.Session.Events.{TranscriptFailed, TranscriptReady, TranscriptionFinished, UtteranceCompleted}
  alias Jotty.Session.State
  alias Jotty.STT.TranscriptionChunk

  @type t :: %__MODULE__{chunks: [TranscriptionChunk.t()]}

  defstruct chunks: []

  @spec new(keyword()) :: t()
  def new(_options), do: %__MODULE__{}

  @impl true
  def subscriptions, do: [UtteranceCompleted, TranscriptionFinished]

  @impl true
  def handle_message(%UtteranceCompleted{chunks: chunks}, %State{} = state) do
    transcript = %{state.transcript | chunks: state.transcript.chunks ++ chunks}
    %{state | transcript: transcript}
  end

  def handle_message(%TranscriptionFinished{}, %State{} = state) do
    path = state.recording.recording.transcript

    case File.write(path, render(state.transcript.chunks)) do
      :ok ->
        Logger.info("ready", scope: :transcript)
        Events.publish(state, %TranscriptReady{path: path})

      {:error, reason} ->
        Logger.error("failed", scope: :transcript, reason: inspect(reason))
        Events.publish(state, %TranscriptFailed{reason: reason})
    end
  end

  defp render(chunks) do
    Enum.map_join(chunks, "\n\n", fn %TranscriptionChunk{speaker: speaker, text: text} ->
      "Speaker #{speaker}: #{String.trim(text)}"
    end)
  end
end
