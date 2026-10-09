defmodule Jotty.Settings.Microphone do
  @moduledoc false

  @type t :: %__MODULE__{id: String.t(), name: String.t()}

  @enforce_keys ~w(id name)a
  defstruct ~w(id name)a
end
