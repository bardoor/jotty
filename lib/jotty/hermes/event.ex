defmodule Jotty.Hermes.Event do
  @moduledoc false

  @type type :: :init | :text | :tool_use | :tool_result | :result
  @type t :: %__MODULE__{
          type: type(),
          name: String.t() | nil,
          input: map() | nil,
          duration_ms: non_neg_integer() | nil,
          is_error: boolean(),
          text: String.t() | nil,
          exit_code: non_neg_integer() | nil,
          error: String.t() | nil
        }

  @enforce_keys ~w(type)a
  defstruct ~w(type name input duration_ms text exit_code error)a ++ [is_error: false]
end
