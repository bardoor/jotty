defmodule Jotty.Session.Events.TaskCardUpdated do
  @moduledoc false

  alias Jotty.Tasks.Card

  @type t :: %__MODULE__{card: Card.t()}
  @enforce_keys ~w(card)a
  defstruct ~w(card)a
end
