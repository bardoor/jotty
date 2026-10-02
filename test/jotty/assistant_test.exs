defmodule Jotty.AssistantTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jotty.Assistant
  alias Jotty.Session.Events.UtteranceCompleted
  alias Jotty.STT.TranscriptionChunk

  @tag :tmp_dir
  test "searches context only for utterances that require project facts", %{tmp_dir: directory} do
    home = Path.join(directory, "home")
    backend = Path.join(directory, "backend")
    frontend = Path.join(directory, "frontend")
    bin_directory = Path.join(directory, "bin")
    codex_calls = Path.join(directory, "codex-calls")
    codex_prompt = Path.join(directory, "codex-prompt")
    hermes_calls = Path.join(directory, "hermes-calls")
    hermes_prompt = Path.join(directory, "hermes-prompt")

    File.mkdir_p!(home)
    File.mkdir_p!(backend)
    File.mkdir_p!(frontend)
    File.mkdir_p!(bin_directory)

    File.write!(Path.join(backend, "translator.ex"), "translator prompt source")
    write_fake_codex!(bin_directory)
    write_fake_hermes!(bin_directory)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    System.put_env("JOTTY_CODEX_CALLS", codex_calls)
    System.put_env("JOTTY_CODEX_PROMPT", codex_prompt)
    System.put_env("JOTTY_HERMES_CALLS", hermes_calls)
    System.put_env("JOTTY_HERMES_PROMPT", hermes_prompt)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      System.delete_env("JOTTY_CODEX_CALLS")
      System.delete_env("JOTTY_CODEX_PROMPT")
      System.delete_env("JOTTY_HERMES_CALLS")
      System.delete_env("JOTTY_HERMES_PROMPT")
    end)

    started_at = ~U[2026-09-23 12:34:56Z]

    assert {:ok, output_path} =
             Assistant.run(
               home,
               [backend, frontend],
               [
                 "Let's split the task into two parts.\n",
                 "What prompt does our translator currently use?\n"
               ],
               started_at
             )

    assert output_path ==
             Path.join([home, ".jotty", "sessions", "20260923-123456", "assistant.md"])

    output = File.read!(output_path)
    assert output =~ "## Find the current Translator prompt"
    assert output =~ "What prompt does our translator currently use?"
    assert output =~ "translator.ex"
    refute output =~ "Let's split the task"

    assert File.read!(codex_calls) == "call\ncall\n"
    assert File.read!(hermes_calls) == "call\n"

    classifier_prompt = File.read!(codex_prompt)
    refute classifier_prompt =~ backend
    refute classifier_prompt =~ frontend

    search_prompt = File.read!(hermes_prompt)
    assert search_prompt =~ backend
    assert search_prompt =~ frontend
    assert search_prompt =~ "all allowed directories"
  end

  @tag :tmp_dir
  test "rejects a missing context directory before starting the session", %{tmp_dir: directory} do
    missing = Path.join(directory, "missing")

    assert {:error, {:context_directory_not_found, ^missing}} =
             Assistant.run(directory, [missing], [], ~U[2026-09-23 12:34:56Z])
  end

  @tag :tmp_dir
  test "processes completed utterances sequentially into the recording assistant artifact", %{
    tmp_dir: directory
  } do
    recording_directory = Path.join(directory, "recording")
    context_directory = Path.join(directory, "backend")
    bin_directory = Path.join(directory, "bin")
    codex_calls = Path.join(directory, "codex-calls")
    codex_prompt = Path.join(directory, "codex-prompt")
    hermes_calls = Path.join(directory, "hermes-calls")
    hermes_prompt = Path.join(directory, "hermes-prompt")

    File.mkdir_p!(recording_directory)
    File.mkdir_p!(context_directory)
    File.mkdir_p!(bin_directory)
    write_fake_codex!(bin_directory)
    write_fake_hermes!(bin_directory)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    System.put_env("JOTTY_CODEX_CALLS", codex_calls)
    System.put_env("JOTTY_CODEX_PROMPT", codex_prompt)
    System.put_env("JOTTY_HERMES_CALLS", hermes_calls)
    System.put_env("JOTTY_HERMES_PROMPT", hermes_prompt)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      System.delete_env("JOTTY_CODEX_CALLS")
      System.delete_env("JOTTY_CODEX_PROMPT")
      System.delete_env("JOTTY_HERMES_CALLS")
      System.delete_env("JOTTY_HERMES_PROMPT")
    end)

    assert {:ok, assistant} = Assistant.start(recording_directory, [context_directory])

    Assistant.submit(
      assistant,
      %UtteranceCompleted{
        chunks: [chunk("Let's split the task into two parts.")]
      }
    )

    Assistant.submit(
      assistant,
      %UtteranceCompleted{
        chunks: [chunk("What prompt does our translator currently use?")]
      }
    )

    output_path = Path.join(recording_directory, "assistant.md")
    assert {:ok, ^output_path} = Assistant.finish(assistant)
    assert File.read!(codex_calls) == "call\ncall\n"
    assert File.read!(hermes_calls) == "call\n"

    output = File.read!(output_path)
    assert output =~ "## Find the current Translator prompt"
    assert output =~ "What prompt does our translator currently use?"
    refute output =~ "Let's split the task"
  end

  @tag :tmp_dir
  test "reports one bounded classifier failure and stops further processing", %{
    tmp_dir: directory
  } do
    recording_directory = Path.join(directory, "recording")
    context_directory = Path.join(directory, "context")
    bin_directory = Path.join(directory, "bin")
    File.mkdir_p!(recording_directory)
    File.mkdir_p!(context_directory)
    File.mkdir_p!(bin_directory)

    write_failing_codex!(bin_directory)
    write_fake_hermes!(bin_directory)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    on_exit(fn -> System.put_env("PATH", original_path) end)

    Logger.metadata(session_id: "<0.123.0>")
    {:ok, assistant} = Assistant.start(recording_directory, [context_directory])
    event = %UtteranceCompleted{chunks: [chunk("Look this up")]}

    log =
      capture_log([metadata: [:stage, :session_id]], fn ->
        Assistant.submit(assistant, event)
        Assistant.submit(assistant, event)
        assert {:error, {:codex, "classifier failed"}} = Assistant.finish(assistant)
        Logger.flush()
      end)

    assert log =~ "lookup_failed"
    assert log =~ "stage=classifier"
    assert log =~ "session_id=<0.123.0>"
    refute log =~ "Look this up"
  end

  defp chunk(text) do
    %TranscriptionChunk{speaker: "1", text: text, start_ms: 0, end_ms: 100}
  end

  defp write_fake_codex!(bin_directory) do
    path = Path.join(bin_directory, "codex")

    File.write!(path, """
    #!/bin/sh
    prompt=$(cat)
    output=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output-last-message" ]; then
        shift
        output="$1"
      fi
      shift
    done
    printf 'call\n' >> "$JOTTY_CODEX_CALLS"
    printf '%s' "$prompt" > "$JOTTY_CODEX_PROMPT"
    case "$prompt" in
      *"What prompt does our translator currently use?"*)
        printf '%s' '{"decision":{"action":"search","query":"Find the current Translator prompt"}}' > "$output"
        ;;
      *)
        printf '%s' '{"decision":{"action":"ignore"}}' > "$output"
        ;;
    esac
    """)

    File.chmod!(path, 0o755)
  end

  defp write_failing_codex!(bin_directory) do
    path = Path.join(bin_directory, "codex")

    File.write!(path, """
    #!/bin/sh
    printf 'classifier failed\n'
    exit 2
    """)

    File.chmod!(path, 0o755)
  end

  defp write_fake_hermes!(bin_directory) do
    path = Path.join(bin_directory, "hermes")

    File.write!(path, """
    #!/bin/sh
    printf 'call\n' >> "$JOTTY_HERMES_CALLS"
    printf '%s' "$2" > "$JOTTY_HERMES_PROMPT"
    printf 'The prompt is defined in `translator.ex`.\n'
    """)

    File.chmod!(path, 0o755)
  end
end
