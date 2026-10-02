defmodule Jotty.Session.Events.ProcessExited do
  @moduledoc false

  @enforce_keys [:reference, :pid, :reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{reference: reference(), pid: pid(), reason: term()}
end
