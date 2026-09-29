defmodule Jotty.STT.Soniox.Token do
  @moduledoc false

  @enforce_keys [:text, :final?, :start_ms, :end_ms, :speaker]
  defstruct [:text, :final?, :start_ms, :end_ms, :speaker]

  @type t :: %__MODULE__{
          text: nonempty_binary(),
          final?: boolean(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer(),
          speaker: nonempty_binary()
        }

  @spec new(map()) :: t() | :endpoint
  def new(%{"text" => "<end>", "is_final" => true}), do: :endpoint

  def new(%{
        "text" => text,
        "is_final" => final?,
        "start_ms" => start_ms,
        "end_ms" => end_ms,
        "speaker" => speaker
      }) do
    %__MODULE__{
      text: text,
      final?: final?,
      start_ms: start_ms,
      end_ms: end_ms,
      speaker: speaker
    }
  end
end
