defmodule Jotty.Desktop.Commands.ReorderContexts do
  @moduledoc false
  @type t :: %__MODULE__{context_ids: [Ecto.UUID.t()]}
  @enforce_keys ~w(context_ids)a
  defstruct ~w(context_ids)a
end
