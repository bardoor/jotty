defmodule Jotty.Settings.Snapshot do
  @moduledoc false

  alias Jotty.Settings.{ContextSnapshot, Microphone}

  @type t :: %__MODULE__{
          always_on_top: boolean(),
          microphone_device_id: String.t() | nil,
          microphone_available: boolean(),
          microphones: [Microphone.t()],
          contexts: [ContextSnapshot.t()]
        }

  @enforce_keys ~w(always_on_top microphone_device_id microphone_available microphones contexts)a
  defstruct ~w(always_on_top microphone_device_id microphone_available microphones contexts)a
end
