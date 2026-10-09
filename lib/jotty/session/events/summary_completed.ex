defmodule Jotty.Session.Events.SummaryCompleted do
  @moduledoc false

  @type t :: %__MODULE__{result: :ok | {:error, term()}}

  @enforce_keys ~w(result)a
  defstruct ~w(result)a
end
