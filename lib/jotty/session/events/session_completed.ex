defmodule Jotty.Session.Events.SessionCompleted do
  @moduledoc false

  @type t :: %__MODULE__{result: {:ok, Jotty.Recording.t()}}

  @enforce_keys ~w(result)a
  defstruct ~w(result)a
end
