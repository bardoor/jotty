defmodule Jotty.Desktop.Commands.ChangeAlwaysOnTop do
  @moduledoc false
  @type t :: %__MODULE__{enabled: boolean()}
  @enforce_keys ~w(enabled)a
  defstruct ~w(enabled)a
end
