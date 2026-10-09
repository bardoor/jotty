defmodule Jotty.InsightsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jotty.Insights
  alias Jotty.Session.Events.HermesActivityObserved
  alias Jotty.Session.Events.UtteranceCompleted
  alias Jotty.STT.TranscriptionChunk

  @tag :tmp_dir
  test "uses Hermes for classification and project-context retrieval", %{tmp_dir: directory} do
    paths = prepare_fake_runtime!(directory)
    started_at = ~U[2026-09-23 12:34:56Z]

    assert {:ok, output_path} =
             Insights.run(
               paths.home,
               [paths.backend, paths.frontend],
               [
                 "Let's split the task into two parts.\n",
                 "What prompt does our translator currently use?\n"
               ],
               started_at
             )

    assert output_path ==
             Path.join([paths.home, ".jotty", "sessions", "20260923-123456", "insights.md"])

    output = File.read!(output_path)
    assert output =~ "## Find the current Translator prompt"
    assert output =~ "What prompt does our translator currently use?"
    assert output =~ "translator.ex"
    refute output =~ "Let's split the task"

    assert File.read!(paths.hermes_calls) == "call\ncall\ncall\n"

    classifier_prompt = File.read!(paths.classifier_prompt)
    refute classifier_prompt =~ paths.backend
    refute classifier_prompt =~ paths.frontend

    search_prompt = File.read!(paths.search_prompt)
    assert search_prompt =~ paths.backend
    assert search_prompt =~ paths.frontend
    assert search_prompt =~ "all allowed directories"
  end

  @tag :tmp_dir
  test "rejects a missing context directory before starting the session", %{tmp_dir: directory} do
    missing = Path.join(directory, "missing")

    assert {:error, {:context_directory_not_found, ^missing}} =
             Insights.run(directory, [missing], [], ~U[2026-09-23 12:34:56Z])
  end

  @tag :tmp_dir
  test "streams retrieval activity while processing completed utterances sequentially", %{
    tmp_dir: directory
  } do
    paths = prepare_fake_runtime!(directory)
    recording_directory = Path.join(directory, "recording")
    File.mkdir_p!(recording_directory)
    owner = self()

    assert {:ok, insights} =
             Insights.start(recording_directory, [paths.backend], &send(owner, {:event, &1}))

    Insights.submit(insights, %UtteranceCompleted{
      chunks: [chunk("Let's split the task into two parts.")]
    })

    Insights.submit(insights, %UtteranceCompleted{
      chunks: [chunk("What prompt does our translator currently use?")]
    })

    output_path = Path.join(recording_directory, "insights.md")
    assert {:ok, ^output_path} = Insights.finish(insights)
    assert File.read!(paths.hermes_calls) == "call\ncall\ncall\n"

    assert_receive {:event,
                    %HermesActivityObserved{
                      stage: :insight_search,
                      status: :running,
                      message: "Searching files for translator"
                    }}

    output = File.read!(output_path)
    assert output =~ "## Find the current Translator prompt"
    assert output =~ "What prompt does our translator currently use?"
    refute output =~ "Let's split the task"
  end

  @tag :tmp_dir
  test "reports one bounded classifier failure and stops further processing", %{tmp_dir: directory} do
    recording_directory = Path.join(directory, "recording")
    context_directory = Path.join(directory, "context")
    bin_directory = Path.join(directory, "bin")
    File.mkdir_p!(recording_directory)
    File.mkdir_p!(context_directory)
    File.mkdir_p!(bin_directory)
    write_failing_hermes!(bin_directory)
    install_path!(bin_directory)

    Logger.metadata(session_id: "<0.123.0>")
    {:ok, insights} = Insights.start(recording_directory, [context_directory])
    event = %UtteranceCompleted{chunks: [chunk("Look this up")]}

    log =
      capture_log([metadata: ~w(stage session_id)a], fn ->
        Insights.submit(insights, event)
        Insights.submit(insights, event)

        assert {:error, {:insight_classification, {:hermes, 2, "classifier failed"}}} =
                 Insights.finish(insights)

        Logger.flush()
      end)

    assert log =~ "lookup_failed"
    assert log =~ "stage=insight_classification"
    assert log =~ "session_id=<0.123.0>"
    refute log =~ "Look this up"
  end

  defp chunk(text) do
    %TranscriptionChunk{speaker: "1", text: text, start_ms: 0, end_ms: 100}
  end

  defp prepare_fake_runtime!(directory) do
    home = Path.join(directory, "home")
    backend = Path.join(directory, "backend")
    frontend = Path.join(directory, "frontend")
    bin_directory = Path.join(directory, "bin")
    File.mkdir_p!(home)
    File.mkdir_p!(backend)
    File.mkdir_p!(frontend)
    File.mkdir_p!(bin_directory)
    File.write!(Path.join(backend, "translator.ex"), "translator prompt source")
    write_fake_hermes!(bin_directory)
    install_path!(bin_directory)

    hermes_calls = Path.join(directory, "hermes-calls")
    classifier_prompt = Path.join(directory, "classifier-prompt")
    search_prompt = Path.join(directory, "search-prompt")
    System.put_env("JOTTY_HERMES_CALLS", hermes_calls)
    System.put_env("JOTTY_CLASSIFIER_PROMPT", classifier_prompt)
    System.put_env("JOTTY_SEARCH_PROMPT", search_prompt)

    on_exit(fn ->
      System.delete_env("JOTTY_HERMES_CALLS")
      System.delete_env("JOTTY_CLASSIFIER_PROMPT")
      System.delete_env("JOTTY_SEARCH_PROMPT")
    end)

    %{
      home: home,
      backend: backend,
      frontend: frontend,
      hermes_calls: hermes_calls,
      classifier_prompt: classifier_prompt,
      search_prompt: search_prompt
    }
  end

  defp install_path!(bin_directory) do
    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    on_exit(fn -> System.put_env("PATH", original_path) end)
  end

  defp write_failing_hermes!(bin_directory) do
    path = Path.join(bin_directory, "hermes")

    File.write!(path, """
    #!/bin/sh
    printf '%s\n' '{"type":"system","subtype":"init"}'
    printf '%s\n' '{"type":"result","exit_code":2,"text":"","error":"classifier failed"}'
    exit 2
    """)

    File.chmod!(path, 0o755)
  end

  defp write_fake_hermes!(bin_directory) do
    path = Path.join(bin_directory, "hermes")

    File.write!(path, """
    #!/bin/sh
    query_file=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--query-file" ]; then
        shift
        query_file="$1"
      fi
      shift
    done
    prompt=$(/bin/cat "$query_file")
    printf 'call\n' >> "$JOTTY_HERMES_CALLS"
    printf '%s\n' '{"type":"system","subtype":"init"}'
    case "$prompt" in
      *"Decide whether"*)
        printf '%s' "$prompt" > "$JOTTY_CLASSIFIER_PROMPT"
        case "$prompt" in
          *"What prompt does our translator currently use?"*)
            printf '%s\n' '{"type":"result","exit_code":0,"text":"{\\"decision\\":{\\"action\\":\\"search\\",\\"query\\":\\"Find the current Translator prompt\\"}}"}'
            ;;
          *)
            printf '%s\n' '{"type":"result","exit_code":0,"text":"{\\"decision\\":{\\"action\\":\\"ignore\\"}}"}'
            ;;
        esac
        ;;
      *)
        printf '%s' "$prompt" > "$JOTTY_SEARCH_PROMPT"
        printf '%s\n' '{"type":"tool_use","name":"search_files","input":{"pattern":"translator"}}'
        printf '%s\n' '{"type":"tool_result","name":"search_files","duration_ms":3,"is_error":false}'
        printf '%s\n' '{"type":"result","exit_code":0,"text":"The prompt is defined in `translator.ex`."}'
        ;;
    esac
    """)

    File.chmod!(path, 0o755)
  end
end
