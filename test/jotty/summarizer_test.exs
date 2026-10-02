defmodule Jotty.SummarizerTest do
  use ExUnit.Case, async: false

  alias Jotty.Summarizer

  @tag :tmp_dir
  test "uses Codex OAuth to write a decision-focused Markdown summary", %{tmp_dir: directory} do
    transcript_path = Path.join(directory, "transcript.txt")
    summary_path = Path.join(directory, "summary.md")
    captured_prompt = Path.join(directory, "prompt.txt")
    bin_directory = Path.join(directory, "bin")
    codex_path = Path.join(bin_directory, "codex")

    File.mkdir!(bin_directory)
    File.write!(transcript_path, "Speaker 1: We decided to ship on Friday.")
    File.write!(codex_path, fake_codex())
    File.chmod!(codex_path, 0o755)
    File.mkdir!(Path.join(directory, "jotty-summary-1"))

    original_path = System.get_env("PATH")
    original_tmp_dir = System.get_env("TMPDIR")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    System.put_env("TMPDIR", directory)
    System.put_env("JOTTY_CAPTURED_PROMPT", captured_prompt)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      restore_environment("TMPDIR", original_tmp_dir)
      System.delete_env("JOTTY_CAPTURED_PROMPT")
    end)

    assert :ok = Summarizer.summarize(transcript_path, summary_path)
    assert File.read!(summary_path) == "# Summary\nEverything happened.\n"

    prompt = File.read!(captured_prompt)
    assert prompt =~ "every accepted decision as a separate bullet"
    assert prompt =~ "Do not turn proposals into accepted decisions"
    assert prompt =~ "Speaker 1: We decided to ship on Friday."
  end

  defp fake_codex do
    """
    #!/bin/sh
    output=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output-last-message" ]; then
        shift
        output="$1"
      fi
      shift
    done
    /bin/cat > "$JOTTY_CAPTURED_PROMPT"
    /usr/bin/printf '# Summary\nEverything happened.\n' > "$output"
    """
  end

  defp restore_environment(name, nil), do: System.delete_env(name)
  defp restore_environment(name, value), do: System.put_env(name, value)
end
