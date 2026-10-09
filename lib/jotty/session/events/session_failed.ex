defmodule Jotty.Session.Events.SessionFailed do
  @moduledoc false

  @type t :: %__MODULE__{reason: term()}

  @enforce_keys ~w(reason)a
  defstruct ~w(reason)a
end
