defmodule Jotty.Session.Events.SummaryCompleted do
  @moduledoc false

  @enforce_keys [:result]
  defstruct @enforce_keys

  @type t :: %__MODULE__{result: :ok | {:error, term()}}
end
