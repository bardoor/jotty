defmodule Jotty.Desktop.Commands.OpenSession do
  @moduledoc false
  @type t :: %__MODULE__{id: Ecto.UUID.t()}
  @enforce_keys ~w(id)a
  defstruct ~w(id)a
end
