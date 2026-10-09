defmodule Jotty.Session.Events.HermesActivityObserved do
  @moduledoc false

  @type status :: :started | :running | :completed | :failed
  @type t :: %__MODULE__{stage: atom(), status: status(), message: String.t()}

  @enforce_keys ~w(stage status message)a
  defstruct ~w(stage status message)a
end
