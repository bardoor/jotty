defmodule Jotty.HermesTest do
  use ExUnit.Case, async: false

  alias Jotty.Hermes
  alias Jotty.Hermes.Event

  @tag :tmp_dir
  test "returns the final response and streams typed JSON events", %{tmp_dir: directory} do
    executable = write_fake_hermes!(directory)
    prompt_path = Path.join(directory, "captured-prompt")
    System.put_env("JOTTY_CAPTURED_PROMPT", prompt_path)
    on_exit(fn -> System.delete_env("JOTTY_CAPTURED_PROMPT") end)
    owner = self()

    assert {:ok, "# Summary\nDone."} =
             Hermes.run(executable, "Summarize this", directory, ["file"], fn event ->
               send(owner, {:hermes_event, event})
             end)

    assert File.read!(prompt_path) == "Summarize this"
    assert_receive {:hermes_event, %Event{type: :init}}

    assert_receive {:hermes_event,
                    %Event{type: :tool_use, name: "read_file", input: %{"path" => "transcript.txt"}}}

    assert_receive {:hermes_event,
                    %Event{type: :tool_result, name: "read_file", duration_ms: 12, is_error: false}}

    assert_receive {:hermes_event, %Event{type: :text}}
    assert_receive {:hermes_event, %Event{type: :result}}
  end

  @tag :tmp_dir
  test "returns a bounded Hermes failure from the terminal result", %{tmp_dir: directory} do
    executable = Path.join(directory, "hermes")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\n' '{"type":"system","subtype":"init"}'
    printf '%s\n' '{"type":"result","exit_code":1,"text":"","error":"provider unavailable"}'
    exit 1
    """)

    File.chmod!(executable, 0o755)

    assert {:error, {:hermes, 1, "provider unavailable"}} =
             Hermes.run(executable, "Prompt", directory, ["file"], fn _event -> :ok end)
  end

  @tag :tmp_dir
  test "maps an empty tool list to Hermes' tool-free toolset", %{tmp_dir: directory} do
    executable = write_fake_hermes!(directory)
    prompt_path = Path.join(directory, "captured-prompt")
    arguments_path = Path.join(directory, "captured-arguments")
    System.put_env("JOTTY_CAPTURED_PROMPT", prompt_path)
    System.put_env("JOTTY_CAPTURED_ARGUMENTS", arguments_path)

    on_exit(fn ->
      System.delete_env("JOTTY_CAPTURED_PROMPT")
      System.delete_env("JOTTY_CAPTURED_ARGUMENTS")
    end)

    assert {:ok, _summary} = Hermes.run(executable, "Prompt", directory, [], fn _event -> :ok end)
    assert File.read!(arguments_path) =~ "--toolsets\nbot_room\n"
  end

  defp write_fake_hermes!(directory) do
    executable = Path.join(directory, "hermes")

    File.write!(executable, """
    #!/bin/sh
    if [ -n "$JOTTY_CAPTURED_ARGUMENTS" ]; then
      /usr/bin/printf '%s\n' "$@" > "$JOTTY_CAPTURED_ARGUMENTS"
    fi
    query_file=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--query-file" ]; then
        shift
        query_file="$1"
      fi
      shift
    done
    /bin/cat "$query_file" > "$JOTTY_CAPTURED_PROMPT"
    printf '%s\n' '{"type":"system","subtype":"init","model":"test"}'
    printf '%s\n' '{"type":"tool_use","name":"read_file","input":{"path":"transcript.txt"}}'
    printf '%s\n' '{"type":"tool_result","name":"read_file","duration_ms":12,"is_error":false}'
    printf '%s\n' '{"type":"text","text":"# Summary"}'
    printf '%s\n' '{"type":"result","exit_code":0,"text":"# Summary\\nDone."}'
    """)

    File.chmod!(executable, 0o755)
    executable
  end
end
