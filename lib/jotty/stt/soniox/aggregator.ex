defmodule Jotty.STT.Soniox.Aggregator do
  @moduledoc false

  alias Jotty.STT.Soniox.Token
  alias Jotty.STT.TranscriptionChunk

  defstruct finalized: []

  @type t :: %__MODULE__{
          finalized: [Token.t()]
        }
  @type event :: {:preview | :completed, [TranscriptionChunk.t()]}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec consume(t(), {:batch, [Token.t() | :endpoint]} | :finished) ::
          {t(), [event()]}
  def consume(%__MODULE__{} = state, {:batch, items}) do
    {before_endpoint, from_endpoint} = Enum.split_while(items, &(&1 != :endpoint))

    case from_endpoint do
      [] -> consume_streaming(state, before_endpoint)
      [:endpoint | next_tokens] -> consume_endpoint(state, before_endpoint, next_tokens)
    end
  end

  def consume(%__MODULE__{finalized: finalized} = state, :finished) do
    state = %{state | finalized: []}
    {state, event(:completed, finalized)}
  end

  defp consume_streaming(%{finalized: finalized} = state, tokens) do
    state = %{state | finalized: finalized ++ finalized(tokens)}
    {state, event(:preview, finalized ++ tokens)}
  end

  defp consume_endpoint(%{finalized: finalized} = state, tokens, next_tokens) do
    completed = finalized ++ finalized(tokens)
    state = %{state | finalized: finalized(next_tokens)}
    events = event(:completed, completed) ++ event(:preview, next_tokens)
    {state, events}
  end

  defp finalized(tokens) do
    Enum.filter(tokens, fn %Token{final?: final?} -> final? end)
  end

  defp event(_type, []), do: []
  defp event(type, tokens), do: [{type, chunks(tokens)}]

  defp chunks(tokens) do
    tokens
    |> Enum.chunk_by(fn %Token{speaker: speaker} -> speaker end)
    |> Enum.map(fn [%Token{speaker: speaker} | _] = speaker_tokens ->
      %Token{start_ms: start_ms} =
        Enum.min_by(speaker_tokens, fn %Token{start_ms: start_ms} -> start_ms end)

      %Token{end_ms: end_ms} =
        Enum.max_by(speaker_tokens, fn %Token{end_ms: end_ms} -> end_ms end)

      text = Enum.map_join(speaker_tokens, fn %Token{text: text} -> text end)

      %TranscriptionChunk{
        speaker: speaker,
        text: text,
        start_ms: start_ms,
        end_ms: end_ms
      }
    end)
  end
end
