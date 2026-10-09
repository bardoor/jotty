defmodule Jotty.STT.Soniox.AggregatorTest do
  use ExUnit.Case, async: true

  alias Jotty.STT.Soniox.{Aggregator, Token}
  alias Jotty.STT.TranscriptionChunk

  test "replaces provisional suffix while retaining final tokens once" do
    state = %Aggregator{}

    assert {state, [{:preview, [%TranscriptionChunk{text: "We should"}]}]} =
             Aggregator.consume(
               state,
               {:batch, [token("We", true, 0, 20), token(" should", false, 20, 50)]}
             )

    assert {_state, [{:preview, [%TranscriptionChunk{text: "We should search"}]}]} =
             Aggregator.consume(state, {:batch, [token(" should search", false, 20, 80)]})
  end

  test "groups contiguous speaker runs" do
    tokens = [
      token("A", true, 0, 10, "1"),
      token(" B", true, 10, 20, "1"),
      token(" C", true, 20, 30, "2"),
      token(" D", true, 30, 40, "1")
    ]

    assert {_state, [{:preview, chunks}]} = Aggregator.consume(%Aggregator{}, {:batch, tokens})

    assert [
             %TranscriptionChunk{speaker: "1", text: "A B", start_ms: 0, end_ms: 20},
             %TranscriptionChunk{speaker: "2", text: " C", start_ms: 20, end_ms: 30},
             %TranscriptionChunk{speaker: "1", text: " D", start_ms: 30, end_ms: 40}
           ] = chunks
  end

  test "completes at endpoint and previews the next utterance" do
    tokens = [token("A", true, 0, 10), :endpoint, token("B", false, 20, 30)]

    assert {state,
            [
              {:completed, [%TranscriptionChunk{text: "A"}]},
              {:preview, [%TranscriptionChunk{text: "B"}]}
            ]} = Aggregator.consume(%Aggregator{}, {:batch, tokens})

    assert {_state, [{:completed, [%TranscriptionChunk{text: "B"}]}]} =
             Aggregator.consume(state, {:batch, [token("B", true, 20, 30), :endpoint]})
  end

  test "completes every endpoint and preserves speaker runs in one provider batch" do
    tokens = [
      token("A", true, 0, 10, "1"),
      :endpoint,
      token("B", true, 20, 30, "2"),
      token(" C", true, 30, 40, "1"),
      :endpoint,
      token("D", false, 50, 60, "2")
    ]

    assert {state,
            [
              {:completed, [%TranscriptionChunk{speaker: "1", text: "A"}]},
              {:completed,
               [
                 %TranscriptionChunk{speaker: "2", text: "B"},
                 %TranscriptionChunk{speaker: "1", text: " C"}
               ]},
              {:preview, [%TranscriptionChunk{speaker: "2", text: "D"}]}
            ]} = Aggregator.consume(%Aggregator{}, {:batch, tokens})

    assert state.finalized == []
  end

  test "finished completes only buffered final content" do
    assert {state, [_preview]} =
             Aggregator.consume(%Aggregator{}, {:batch, [token("last", true, 0, 10)]})

    assert {_state, [{:completed, [%TranscriptionChunk{text: "last"}]}]} =
             Aggregator.consume(state, :finished)

    assert {state, [_preview]} =
             Aggregator.consume(%Aggregator{}, {:batch, [token("draft", false, 0, 10)]})

    assert {_state, []} = Aggregator.consume(state, :finished)
  end

  defp token(text, final?, start_ms, end_ms, speaker \\ "1") do
    %Token{text: text, final?: final?, start_ms: start_ms, end_ms: end_ms, speaker: speaker}
  end
end
