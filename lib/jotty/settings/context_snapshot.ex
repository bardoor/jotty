defmodule Jotty.Settings.ContextSnapshot do
  @moduledoc false

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          path: Path.t(),
          position: non_neg_integer(),
          available: boolean()
        }

  @enforce_keys ~w(id name path position available)a
  defstruct ~w(id name path position available)a
end
