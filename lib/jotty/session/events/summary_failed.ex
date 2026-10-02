defmodule Jotty.Session.Events.SummaryFailed do
  @moduledoc false

  @enforce_keys [:reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{reason: term()}
end
