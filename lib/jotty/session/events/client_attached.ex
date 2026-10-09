defmodule Jotty.Session.Events.ClientAttached do
  @moduledoc false

  @type t :: %__MODULE__{client: pid()}

  @enforce_keys ~w(client)a
  defstruct ~w(client)a
end
