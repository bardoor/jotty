defmodule Jotty.Session.Events.SummaryReady do
  @moduledoc false

  @enforce_keys [:recording, :markdown]
  defstruct @enforce_keys

  @type t :: %__MODULE__{recording: Jotty.Recording.t(), markdown: String.t()}
end
