defmodule Jotty.Desktop.Commands.ApproveTask do
  @moduledoc false

  @type t :: %__MODULE__{card_id: Ecto.UUID.t()}
  @enforce_keys ~w(card_id)a
  defstruct ~w(card_id)a
end
