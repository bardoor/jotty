defmodule Jotty.Session.Events.TaskSearchStarted do
  @moduledoc false

  @type t :: %__MODULE__{query: String.t()}
  @enforce_keys ~w(query)a
  defstruct ~w(query)a
end
