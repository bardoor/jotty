defmodule Jotty.Session.Events.TranscriptReady do
  @moduledoc false

  @enforce_keys [:path]
  defstruct @enforce_keys

  @type t :: %__MODULE__{path: Path.t()}
end
