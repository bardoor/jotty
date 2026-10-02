defmodule Jotty.CLI do
  @moduledoc false

  alias Jotty.Desktop.Server
  alias Jotty.Recording

  @spec main([String.t()]) :: no_return()
  def main(arguments) do
    case run(arguments) do
      {:ok, %Server{} = server} ->
        IO.puts(Jason.encode!(%{type: "ready", websocket_url: "ws://127.0.0.1:#{server.port}/ws"}))
        Process.sleep(:infinity)

      {:ok, result} ->
        IO.puts(success_path(result))
        System.halt(0)

      {:error, :usage} ->
        print_usage()
        System.halt(64)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
        System.halt(1)
    end
  end

  @doc """
  Validates the command and runs one complete recording workflow.
  """
  @spec run([String.t()]) :: {:ok, Jotty.Recording.t() | Path.t() | Server.t()} | {:error, term()}
  def run(["record" | arguments]) do
    parsed = OptionParser.parse(arguments, strict: [context: :keep])
    run_record(parsed)
  end

  def run(["enrich", recording_directory | arguments]) do
    switches = [context: :string, model: :string, reasoning_effort: :string]

    with {options, [], []} <- OptionParser.parse(arguments, strict: switches),
         {:ok, context_directory} <- Keyword.fetch(options, :context) do
      enrichment_options = Keyword.take(options, [:model, :reasoning_effort])
      Jotty.Enricher.enrich(recording_directory, context_directory, enrichment_options)
    else
      _invalid_arguments -> {:error, :usage}
    end
  end

  def run(["assist" | arguments]) do
    parsed = OptionParser.parse(arguments, strict: [context: :keep])
    run_assistant(parsed)
  end

  def run(["serve" | arguments]) do
    parsed = OptionParser.parse(arguments, strict: [port: :integer])
    run_server(parsed)
  end

  def run(_arguments), do: {:error, :usage}

  defp run_record({options, [], []}) do
    context_directories = Keyword.get_values(options, :context)
    home = System.user_home!()
    recorded_at = DateTime.utc_now()

    with :ok <- Jotty.Assistant.validate_contexts(context_directories),
         {:ok, api_key} <- fetch_api_key(),
         {:ok, recorder} <- native_recorder() do
      Jotty.record(home, recorder, api_key, recorded_at, contexts: context_directories)
    end
  end

  defp run_record(_invalid_arguments), do: {:error, :usage}

  defp run_assistant({options, [], []}) do
    context_directories = Keyword.get_values(options, :context)
    home = System.user_home!()
    utterances = IO.stream(:stdio, :line)
    started_at = DateTime.utc_now()

    if context_directories == [] do
      {:error, :usage}
    else
      Jotty.Assistant.run(home, context_directories, utterances, started_at)
    end
  end

  defp run_assistant(_invalid_arguments), do: {:error, :usage}

  defp run_server({options, [], []}) do
    port = Keyword.get(options, :port, 4_765)
    home = System.user_home!()

    with {:ok, api_key} <- fetch_api_key(),
         {:ok, recorder} <- native_recorder() do
      session_options = [
        api_key: api_key,
        recorder: recorder,
        recorder_options: [stop: :message],
        recording: fn -> Recording.create!(home, DateTime.utc_now()) end
      ]

      Server.start(session_options: session_options, port: port)
    end
  end

  defp run_server(_invalid_arguments), do: {:error, :usage}

  defp success_path(%Jotty.Recording{directory: directory}), do: directory
  defp success_path(path) when is_binary(path), do: path

  defp print_usage do
    usage =
      "Usage:\n  jotty record [--context CONTEXT_DIRECTORY ...]\n  jotty serve [--port PORT]\n  jotty enrich RECORDING_DIRECTORY --context CONTEXT_DIRECTORY [--model MODEL] [--reasoning-effort EFFORT]\n  jotty assist --context CONTEXT_DIRECTORY [--context CONTEXT_DIRECTORY ...]"

    IO.puts(:stderr, usage)
  end

  defp fetch_api_key do
    case Application.fetch_env(:jotty, :soniox_api_key) do
      {:ok, api_key} -> {:ok, api_key}
      :error -> {:error, {:missing_configuration, :soniox_api_key}}
    end
  end

  defp native_recorder do
    script_path = :escript.script_name() |> to_string() |> Path.expand()

    path =
      Path.join([
        Path.dirname(script_path),
        "native",
        "recorder",
        ".build",
        "release",
        "jotty-recorder"
      ])

    if File.regular?(path) do
      {:ok, path}
    else
      {:error, {:native_recorder_not_found, path}}
    end
  end

  defp format_error({:missing_configuration, key}) do
    "configuration #{key} is not set in config/dev.secret.exs"
  end

  defp format_error({:native_recorder_not_found, path}) do
    "native recorder not found at #{path}"
  end

  defp format_error({:recorder, status}), do: "native recorder exited with status #{status}"

  defp format_error({:recorder_signal, status, output}) do
    "could not stop native recorder (status #{status}): #{output}"
  end

  defp format_error({:codex, output}), do: "Codex failed: #{output}"
  defp format_error({:transcript_not_found, path}), do: "transcript not found at #{path}"

  defp format_error({:context_directory_not_found, path}) do
    "context directory not found at #{path}"
  end

  defp format_error(:hermes_not_found), do: "hermes executable was not found in PATH"
  defp format_error(:codex_not_found), do: "codex executable was not found in PATH"

  defp format_error({:hermes, status, output}) do
    "Hermes failed with status #{status}: #{output}"
  end

  defp format_error(reason), do: inspect(reason)
end
