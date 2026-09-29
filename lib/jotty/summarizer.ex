defmodule Jotty.Summarizer do
  @moduledoc """
  Produces a call summary through the locally authenticated Codex CLI.
  """

  @doc """
  Reads a transcript and writes the final Markdown response returned by Codex.
  """
  @spec summarize(Path.t(), Path.t()) :: :ok | {:error, {:codex, String.t()}}
  def summarize(transcript_path, summary_path) do
    transcript = File.read!(transcript_path)
    workspace = temporary_workspace()
    prompt_path = Path.join(workspace, "prompt.txt")
    response_path = Path.join(workspace, "summary.md")
    File.write!(prompt_path, prompt(transcript))

    try do
      run_codex(workspace, prompt_path, response_path, summary_path)
    after
      File.rm_rf!(workspace)
    end
  end

  defp run_codex(workspace, prompt_path, response_path, summary_path) do
    codex = System.find_executable("codex") || raise "codex executable was not found in PATH"

    shell_command =
      ~S(exec "$1" exec --sandbox read-only --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check --output-last-message "$3" - < "$2")

    result =
      System.cmd(
        "/bin/sh",
        ["-c", shell_command, "jotty-codex", codex, prompt_path, response_path],
        cd: workspace,
        stderr_to_stdout: true
      )

    case result do
      {_output, 0} ->
        File.cp!(response_path, summary_path)
        :ok

      {output, _status} ->
        {:error, {:codex, String.trim(output)}}
    end
  end

  defp prompt(transcript) do
    """
    Summarize the call transcript below as clear Markdown in the transcript's predominant language.

    Include:
    - a concise but meaningful overview;
    - every accepted decision as a separate bullet;
    - tasks, naming an owner or deadline only when explicitly stated;
    - unresolved questions.

    Do not invent facts. Do not turn proposals into accepted decisions. Preserve important qualifications and meaning. Return only the Markdown summary. Do not use tools.

    Transcript:
    <transcript>
    #{transcript}
    </transcript>
    """
  end

  defp temporary_workspace do
    path =
      Path.join(
        System.tmp_dir!(),
        "jotty-summary-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(path)
    path
  end
end
