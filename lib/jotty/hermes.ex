defmodule Jotty.Hermes do
  @moduledoc "Runs one bounded Hermes turn and exposes its JSONL event stream."

  alias Jotty.Hermes.Event
  alias Jotty.TemporaryDirectory

  @type option ::
          {:toolsets, [String.t()]}
          | {:skills, [String.t()]}
          | {:yolo, boolean()}

  @spec run(Path.t(), String.t(), Path.t(), [option()], (Event.t() -> any())) ::
          {:ok, String.t()} | {:error, {:hermes, non_neg_integer(), String.t()}}
  def run(executable, prompt, working_directory, options, on_event) do
    workspace = TemporaryDirectory.create!("jotty-hermes")
    prompt_path = Path.join(workspace, "prompt.txt")
    File.write!(prompt_path, prompt)

    try do
      executable
      |> open(prompt_path, working_directory, options)
      |> await(on_event, nil, "", "")
    after
      File.rm_rf!(workspace)
    end
  end

  defp open(executable, prompt_path, working_directory, options) do
    toolsets = options |> Keyword.fetch!(:toolsets) |> toolset_name()
    skills = Keyword.fetch!(options, :skills)
    yolo = Keyword.fetch!(options, :yolo)
    line_limit = 10_000

    arguments =
      [
        "chat",
        "--query-file",
        prompt_path,
        "--oneshot",
        "--format",
        "stream-json",
        "--model",
        "gpt-5.6-luna",
        "--reasoning",
        "low",
        "--toolsets",
        toolsets,
        "--ignore-rules",
        "--source",
        "tool"
      ] ++ skill_arguments(skills) ++ yolo_arguments(yolo)

    Port.open(
      {:spawn_executable, String.to_charlist(executable)},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :use_stdio,
        {:line, line_limit},
        {:cd, String.to_charlist(working_directory)},
        args: Enum.map(arguments, &String.to_charlist/1)
      ]
    )
  end

  defp toolset_name([]), do: "bot_room"
  defp toolset_name(toolsets), do: Enum.join(toolsets, ",")

  defp skill_arguments([]), do: []
  defp skill_arguments(skills), do: ["--skills", Enum.join(skills, ",")]

  defp yolo_arguments(false), do: []
  defp yolo_arguments(true), do: ["--yolo"]

  defp await(port, on_event, result, partial, diagnostics) do
    timeout = 330_000

    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        await(port, on_event, result, partial <> chunk, diagnostics)

      {^port, {:data, {:eol, chunk}}} ->
        {result, diagnostics} = consume_line(partial <> chunk, on_event, result, diagnostics)
        await(port, on_event, result, "", diagnostics)

      {^port, {:exit_status, status}} ->
        finish(status, result, diagnostics)
    after
      timeout ->
        Port.close(port)
        {:error, {:hermes, 124, "Hermes timed out after 330 seconds"}}
    end
  end

  defp consume_line(line, on_event, result, diagnostics) do
    case Jason.decode(line) do
      {:ok, payload} when is_map(payload) ->
        event = event(payload)
        notify_event(on_event, event)
        result = consume_result(event, payload, result)
        {result, diagnostics}

      _error ->
        {result, append_diagnostic(diagnostics, line)}
    end
  end

  defp event(%{"type" => "system", "subtype" => "init"}), do: %Event{type: :init}
  defp event(%{"type" => "text", "text" => text}), do: %Event{type: :text, text: text}

  defp event(%{"type" => "tool_use", "name" => name} = payload) do
    %Event{type: :tool_use, name: name, input: payload["input"]}
  end

  defp event(%{"type" => "tool_result", "name" => name} = payload) do
    %Event{
      type: :tool_result,
      name: name,
      duration_ms: payload["duration_ms"],
      is_error: payload["is_error"] == true
    }
  end

  defp event(%{"type" => "result"} = payload) do
    %Event{
      type: :result,
      text: payload["text"],
      exit_code: payload["exit_code"],
      error: payload["error"],
      is_error: payload["exit_code"] != 0
    }
  end

  defp event(_payload), do: nil

  defp notify_event(_on_event, nil), do: :ok
  defp notify_event(on_event, event), do: on_event.(event)

  defp consume_result(%Event{type: :result}, payload, _result), do: payload
  defp consume_result(_event, _payload, result), do: result

  defp finish(0, %{"exit_code" => 0, "text" => text}, _diagnostics) when is_binary(text),
    do: {:ok, String.trim(text)}

  defp finish(status, result, diagnostics) do
    exit_code = (result && result["exit_code"]) || status
    reason = result && (result["error"] || result["text"])
    {:error, {:hermes, exit_code, present_reason(reason, diagnostics)}}
  end

  defp present_reason(reason, _diagnostics) when is_binary(reason) and reason != "", do: String.trim(reason)
  defp present_reason(_reason, diagnostics) when diagnostics != "", do: String.trim(diagnostics)
  defp present_reason(_reason, _diagnostics), do: "Hermes exited without a terminal result"

  defp append_diagnostic(diagnostics, line) do
    String.slice(diagnostics <> line <> "\n", 0, 2_000)
  end
end
