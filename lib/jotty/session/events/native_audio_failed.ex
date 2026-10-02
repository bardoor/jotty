defmodule Jotty.Session.Events.NativeAudioFailed do
  @moduledoc false

  @enforce_keys [:source, :reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{source: atom() | nil, reason: term()}
end
