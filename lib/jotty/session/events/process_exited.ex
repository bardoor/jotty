defmodule Jotty.Session.Events.ProcessExited do
  @moduledoc false

  @type t :: %__MODULE__{reference: reference(), pid: pid(), reason: term()}

  @enforce_keys ~w(reference pid reason)a
  defstruct ~w(reference pid reason)a
end
