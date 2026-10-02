defmodule Jotty.Session.Events.UtteranceCompleted do
  @moduledoc false

  alias Jotty.STT.TranscriptionChunk

  @enforce_keys [:chunks]
  defstruct @enforce_keys

  @type t :: %__MODULE__{chunks: [TranscriptionChunk.t()]}
end
