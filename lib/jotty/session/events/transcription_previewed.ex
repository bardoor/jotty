defmodule Jotty.Session.Events.TranscriptionPreviewed do
  @moduledoc false

  alias Jotty.STT.TranscriptionChunk

  @type t :: %__MODULE__{chunks: [TranscriptionChunk.t()]}

  @enforce_keys ~w(chunks)a
  defstruct ~w(chunks)a
end
