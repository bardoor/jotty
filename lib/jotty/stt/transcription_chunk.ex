defmodule Jotty.STT.TranscriptionChunk do
  @moduledoc false

  @enforce_keys [:speaker, :text, :start_ms, :end_ms]
  defstruct [:speaker, :text, :start_ms, :end_ms]

  @type t :: %__MODULE__{
          speaker: nonempty_binary(),
          text: nonempty_binary(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer()
        }
end
