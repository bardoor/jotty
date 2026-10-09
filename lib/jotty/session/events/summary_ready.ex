defmodule Jotty.Session.Events.SummaryReady do
  @moduledoc false

  @type t :: %__MODULE__{recording: Jotty.Recording.t(), markdown: String.t()}

  @enforce_keys ~w(recording markdown)a
  defstruct ~w(recording markdown)a
end
