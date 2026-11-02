defmodule Jotty.Tasks.Change do
  @moduledoc false

  @type field ::
          :title
          | :description
          | :team
          | :project
          | :status
          | :assignee
          | :priority
          | :estimate
          | :cycle
          | :labels

  @type value :: String.t() | number() | boolean() | nil | [String.t()]
  @type t :: %__MODULE__{field: field(), from: value(), to: value()}

  @enforce_keys ~w(field from to)a
  defstruct ~w(field from to)a

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = change) do
    %{field: change.field, from: change.from, to: change.to}
  end

  @spec from_map(map()) :: t()
  def from_map(%{"field" => field, "from" => from, "to" => to}) do
    %__MODULE__{field: field(field), from: from, to: to}
  end

  defp field("title"), do: :title
  defp field("description"), do: :description
  defp field("team"), do: :team
  defp field("project"), do: :project
  defp field("status"), do: :status
  defp field("assignee"), do: :assignee
  defp field("priority"), do: :priority
  defp field("estimate"), do: :estimate
  defp field("cycle"), do: :cycle
  defp field("labels"), do: :labels
end
