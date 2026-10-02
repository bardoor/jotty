defmodule Jotty.Session.Events.ClientAttached do
  @moduledoc false

  @enforce_keys [:client]
  defstruct @enforce_keys

  @type t :: %__MODULE__{client: pid()}
end
