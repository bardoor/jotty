defmodule Jotty.Session.Events.RecorderFinished do
  @moduledoc false

  @enforce_keys [:result]
  defstruct @enforce_keys

  @type t :: %__MODULE__{result: Jotty.Recorder.result()}
end
