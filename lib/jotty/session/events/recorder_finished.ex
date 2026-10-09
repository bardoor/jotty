defmodule Jotty.Session.Events.RecorderFinished do
  @moduledoc false

  @type t :: %__MODULE__{result: Jotty.Recorder.result()}

  @enforce_keys ~w(result)a
  defstruct ~w(result)a
end
