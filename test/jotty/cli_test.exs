defmodule Jotty.CLITest do
  use ExUnit.Case, async: false

  alias Jotty.CLI

  test "rejects unsupported commands" do
    assert {:error, :usage} = CLI.run([])
    assert {:error, :usage} = CLI.run(["unknown"])
    assert {:error, :usage} = CLI.run(["assist"])
    assert {:error, :usage} = CLI.run(["serve", "--port", "invalid"])
  end

  @tag :tmp_dir
  test "preserves every context directory passed to assist", %{tmp_dir: directory} do
    first_directory = Path.join(directory, "first-missing")
    second_directory = Path.join(directory, "second-missing")

    assert {:error, {:context_directory_not_found, ^first_directory}} =
             CLI.run([
               "assist",
               "--context",
               first_directory,
               "--context",
               second_directory
             ])
  end

  test "reads the Soniox key from application configuration" do
    previous_key = Application.get_env(:jotty, :soniox_api_key)
    previous_environment_key = System.get_env("SONIOX_API_KEY")

    on_exit(fn ->
      restore_application_key(previous_key)
      restore_environment_key(previous_environment_key)
    end)

    Application.put_env(:jotty, :soniox_api_key, "configured-key")
    System.delete_env("SONIOX_API_KEY")

    assert {:error, {:native_recorder_not_found, _path}} = CLI.run(["record"])
  end

  test "accepts a desktop server port" do
    previous_key = Application.get_env(:jotty, :soniox_api_key)
    Application.delete_env(:jotty, :soniox_api_key)
    on_exit(fn -> restore_application_key(previous_key) end)

    assert {:error, {:missing_configuration, :soniox_api_key}} =
             CLI.run(["serve", "--port", "4321"])
  end

  @tag :tmp_dir
  test "preserves every context directory passed to record", %{tmp_dir: directory} do
    first_directory = Path.join(directory, "first-missing")
    second_directory = Path.join(directory, "second-missing")

    assert {:error, {:context_directory_not_found, ^first_directory}} =
             CLI.run([
               "record",
               "--context",
               first_directory,
               "--context",
               second_directory
             ])
  end

  @tag :tmp_dir
  test "enriches a recording with the explicitly provided context directory", %{
    tmp_dir: directory
  } do
    fixture = enrichment_fixture(directory)

    assert {:ok, output_path} =
             CLI.run([
               "enrich",
               fixture.recording_directory,
               "--context",
               fixture.context_directory
             ])

    assert output_path == Path.join(fixture.recording_directory, "context.md")
    assert File.read!(output_path) == "# Project context\nRelevant information.\n"
    assert File.read!(fixture.working_directory_path) == fixture.recording_directory <> "\n"

    assert File.read!(fixture.arguments_path <> ".1") == "-z"
    prompt = File.read!(fixture.arguments_path <> ".2")
    assert File.read!(fixture.arguments_path <> ".3") == "--toolsets"
    assert File.read!(fixture.arguments_path <> ".4") == "file,skills,memory"
    assert File.read!(fixture.arguments_path <> ".5") == "--model"
    assert File.read!(fixture.arguments_path <> ".6") == "gpt-5.6-luna"
    assert File.read!(fixture.arguments_path <> ".7") == "--reasoning"
    assert File.read!(fixture.arguments_path <> ".8") == "low"

    assert prompt =~ Path.join(fixture.recording_directory, "transcript.txt")
    assert prompt =~ fixture.context_directory
    assert prompt =~ "dev.secret.exs"
  end

  @tag :tmp_dir
  test "passes an explicitly selected model and reasoning effort to Hermes", %{
    tmp_dir: directory
  } do
    fixture = enrichment_fixture(directory)

    assert {:ok, _output_path} =
             CLI.run([
               "enrich",
               fixture.recording_directory,
               "--context",
               fixture.context_directory,
               "--model",
               "gpt-5.6-sol",
               "--reasoning-effort",
               "medium"
             ])

    assert File.read!(fixture.arguments_path <> ".6") == "gpt-5.6-sol"
    assert File.read!(fixture.arguments_path <> ".8") == "medium"
  end

  defp enrichment_fixture(directory) do
    recording_directory = Path.join(directory, "recording")
    context_directory = Path.join(directory, "project")
    bin_directory = Path.join(directory, "bin")
    arguments_path = Path.join(directory, "arguments")
    working_directory_path = Path.join(directory, "working-directory")

    File.mkdir_p!(recording_directory)
    File.mkdir_p!(context_directory)
    File.mkdir_p!(bin_directory)
    File.write!(Path.join(recording_directory, "transcript.txt"), "We discussed the project.")

    hermes = Path.join(bin_directory, "hermes")

    File.write!(hermes, """
    #!/bin/sh
    printf '%s' "$1" > "$JOTTY_HERMES_ARGUMENTS.1"
    printf '%s' "$2" > "$JOTTY_HERMES_ARGUMENTS.2"
    printf '%s' "$3" > "$JOTTY_HERMES_ARGUMENTS.3"
    printf '%s' "$4" > "$JOTTY_HERMES_ARGUMENTS.4"
    printf '%s' "$5" > "$JOTTY_HERMES_ARGUMENTS.5"
    printf '%s' "$6" > "$JOTTY_HERMES_ARGUMENTS.6"
    printf '%s' "$7" > "$JOTTY_HERMES_ARGUMENTS.7"
    printf '%s' "$8" > "$JOTTY_HERMES_ARGUMENTS.8"
    pwd > "$JOTTY_HERMES_WORKING_DIRECTORY"
    printf '# Project context\nRelevant information.\n'
    """)

    File.chmod!(hermes, 0o755)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    System.put_env("JOTTY_HERMES_ARGUMENTS", arguments_path)
    System.put_env("JOTTY_HERMES_WORKING_DIRECTORY", working_directory_path)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      System.delete_env("JOTTY_HERMES_ARGUMENTS")
      System.delete_env("JOTTY_HERMES_WORKING_DIRECTORY")
    end)

    %{
      arguments_path: arguments_path,
      context_directory: context_directory,
      recording_directory: recording_directory,
      working_directory_path: working_directory_path
    }
  end

  defp restore_application_key(nil), do: Application.delete_env(:jotty, :soniox_api_key)
  defp restore_application_key(key), do: Application.put_env(:jotty, :soniox_api_key, key)

  defp restore_environment_key(nil), do: System.delete_env("SONIOX_API_KEY")
  defp restore_environment_key(key), do: System.put_env("SONIOX_API_KEY", key)
end
