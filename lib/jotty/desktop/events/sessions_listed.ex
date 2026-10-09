defmodule Jotty.Desktop.Events.SessionsListed do
  @moduledoc false
  @type t :: %__MODULE__{sessions: [map()]}
  @enforce_keys ~w(sessions)a
  defstruct ~w(sessions)a
end
