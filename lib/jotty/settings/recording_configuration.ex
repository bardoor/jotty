defmodule Jotty.Settings.RecordingConfiguration do
  @moduledoc false

  @type t :: %__MODULE__{contexts: [Path.t()], microphone_device_id: String.t() | nil}

  @enforce_keys ~w(contexts microphone_device_id)a
  defstruct ~w(contexts microphone_device_id)a
end
