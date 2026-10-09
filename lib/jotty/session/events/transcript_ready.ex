defmodule Jotty.Session.Events.TranscriptReady do
  @moduledoc false

  @type t :: %__MODULE__{path: Path.t()}

  @enforce_keys ~w(path)a
  defstruct ~w(path)a
end
