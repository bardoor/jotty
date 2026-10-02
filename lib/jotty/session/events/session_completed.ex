defmodule Jotty.Session.Events.SessionCompleted do
  @moduledoc false

  @enforce_keys [:result]
  defstruct @enforce_keys

  @type t :: %__MODULE__{result: {:ok, Jotty.Recording.t()}}
end
