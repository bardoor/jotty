defmodule Jotty.Desktop.Events.CommandRejected do
  @moduledoc false
  @type t :: %__MODULE__{command: atom(), reason: String.t()}
  @enforce_keys ~w(command reason)a
  defstruct ~w(command reason)a
end
