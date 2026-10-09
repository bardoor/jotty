defmodule Jotty.Desktop.Commands.DeleteSession do
  @moduledoc false
  @type t :: %__MODULE__{id: Ecto.UUID.t()}
  @enforce_keys ~w(id)a
  defstruct ~w(id)a
end
