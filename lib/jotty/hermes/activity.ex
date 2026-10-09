defmodule Jotty.Hermes.Activity do
  @moduledoc "Projects raw Hermes events into safe user-visible progress."

  alias Jotty.Hermes.Event
  alias Jotty.Session.Events.HermesActivityObserved

  @spec from_event(atom(), Event.t()) :: HermesActivityObserved.t()
  def from_event(stage, %Event{type: :init}) do
    activity(stage, :started, "Starting Hermes")
  end

  def from_event(stage, %Event{type: :tool_use, name: name, input: input}) do
    activity(stage, :running, tool_message(name, input || %{}))
  end

  def from_event(stage, %Event{type: :tool_result, name: name, is_error: true}) do
    activity(stage, :failed, "#{tool_name(name)} failed")
  end

  def from_event(stage, %Event{type: :tool_result, name: name}) do
    activity(stage, :completed, "#{tool_name(name)} completed")
  end

  def from_event(:summary = stage, %Event{type: :text}) do
    activity(stage, :running, "Writing summary")
  end

  def from_event(:insight_classification = stage, %Event{type: :text}) do
    activity(stage, :running, "Classifying insight intent")
  end

  def from_event(:insight_search = stage, %Event{type: :text}) do
    activity(stage, :running, "Writing insight findings")
  end

  def from_event(stage, %Event{type: :result, is_error: true}) do
    activity(stage, :failed, "Hermes failed")
  end

  def from_event(stage, %Event{type: :result}) do
    activity(stage, :completed, "Hermes finished")
  end

  defp activity(stage, status, message) do
    %HermesActivityObserved{stage: stage, status: status, message: message}
  end

  defp tool_message("read_file", %{"path" => path}) when is_binary(path),
    do: "Reading #{Path.basename(path)}"

  defp tool_message("search_files", %{"pattern" => pattern}) when is_binary(pattern),
    do: "Searching files for #{truncate(pattern)}"

  defp tool_message("web_search", %{"query" => query}) when is_binary(query),
    do: "Searching the web for #{truncate(query)}"

  defp tool_message("web_extract", _input), do: "Reading a web source"
  defp tool_message(name, _input), do: "Running #{tool_name(name)}"

  defp tool_name(name) when is_binary(name), do: String.replace(name, "_", " ")
  defp tool_name(_name), do: "tool"

  defp truncate(value) do
    if String.length(value) > 120, do: String.slice(value, 0, 117) <> "…", else: value
  end
end
