defmodule Jotty.STT.TranscriptionChunk do
  @moduledoc false

  @type t :: %__MODULE__{
          speaker: nonempty_binary(),
          text: nonempty_binary(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer()
        }

  @enforce_keys ~w(speaker text start_ms end_ms)a
  defstruct ~w(speaker text start_ms end_ms)a
end
