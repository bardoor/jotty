defmodule Jotty.Session.Events.AudioReceived do
  @moduledoc false

  @enforce_keys [:pcm]
  defstruct @enforce_keys

  @type t :: %__MODULE__{pcm: binary()}
end
