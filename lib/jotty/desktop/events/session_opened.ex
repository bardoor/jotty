defmodule Jotty.Desktop.Events.SessionOpened do
  @moduledoc false
  @type t :: %__MODULE__{session: map()}
  @enforce_keys ~w(session)a
  defstruct ~w(session)a
end
