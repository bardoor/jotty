defmodule Jotty.Desktop.Commands.AddContext do
  @moduledoc false
  @type t :: %__MODULE__{path: Path.t(), approval: String.t()}
  @enforce_keys ~w(path approval)a
  defstruct ~w(path approval)a
end
