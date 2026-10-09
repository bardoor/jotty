defmodule Jotty.Desktop.Commands.RenameSession do
  @moduledoc false
  @type t :: %__MODULE__{id: Ecto.UUID.t(), title: String.t()}
  @enforce_keys ~w(id title)a
  defstruct ~w(id title)a
end
