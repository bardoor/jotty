defmodule Jotty.Desktop.Events.SettingsChanged do
  @moduledoc false

  alias Jotty.Settings.Snapshot

  @type t :: %__MODULE__{snapshot: Snapshot.t(), error: String.t() | nil}

  @enforce_keys ~w(snapshot error)a
  defstruct ~w(snapshot error)a
end
