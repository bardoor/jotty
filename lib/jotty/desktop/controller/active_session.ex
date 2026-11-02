defmodule Jotty.Desktop.Controller.ActiveSession do
  @moduledoc false

  alias Jotty.Recording
  alias Jotty.STT.TranscriptionChunk

  @type phase :: :starting | :recording | :stopping | :completed | {:failed, term()}

  @type t :: %__MODULE__{
          pid: pid(),
          id: Ecto.UUID.t(),
          recording: Recording.t(),
          phase: phase(),
          chunks: [TranscriptionChunk.t()]
        }

  @enforce_keys ~w(pid id recording phase chunks)a
  defstruct ~w(pid id recording phase chunks)a
end
