defmodule Jotty.Session.Events.RealtimeTranscriptionFailed do
  @moduledoc false

  @type t :: %__MODULE__{source: atom() | nil, reason: term()}

  @enforce_keys ~w(source reason)a
  defstruct ~w(source reason)a
end
