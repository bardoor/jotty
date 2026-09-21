defmodule Jotty.CLI do
  @moduledoc false

  @spec main([String.t()]) :: no_return()
  def main(arguments) do
    case run(arguments) do
      {:ok, recording} ->
        IO.puts(recording.directory)
        System.halt(0)

      {:error, :usage} ->
        IO.puts(:stderr, "Usage: jotty record")
        System.halt(64)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
        System.halt(1)
    end
  end

  @doc """
  Validates the command and runs one complete recording workflow.
  """
  @spec run([String.t()]) :: {:ok, Jotty.Recording.t()} | {:error, term()}
  def run(["record"]) do
    with {:ok, api_key} <- fetch_api_key(),
         {:ok, recorder} <- native_recorder() do
      Jotty.record(System.user_home!(), recorder, api_key, DateTime.utc_now())
    end
  end

  def run(_arguments), do: {:error, :usage}

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

  defp format_error({:ffmpeg, output}), do: "FFmpeg failed: #{output}"
  defp format_error({:codex, output}), do: "Codex failed: #{output}"
  defp format_error(reason), do: inspect(reason)
end
