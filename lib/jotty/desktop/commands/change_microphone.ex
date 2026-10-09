defmodule Jotty.Desktop.Commands.ChangeMicrophone do
  @moduledoc false
  @type t :: %__MODULE__{microphone_device_id: String.t() | nil}
  @enforce_keys ~w(microphone_device_id)a
  defstruct ~w(microphone_device_id)a
end
