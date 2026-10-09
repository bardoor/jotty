defmodule Jotty.Session.Events.AudioReceived do
  @moduledoc false

  @type t :: %__MODULE__{pcm: binary()}

  @enforce_keys ~w(pcm)a
  defstruct ~w(pcm)a
end
