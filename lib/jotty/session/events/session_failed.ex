defmodule Jotty.Session.Events.SessionFailed do
  @moduledoc false

  @enforce_keys [:reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{reason: term()}
end
