defmodule Jotty.Tasks.Proposer do
  @moduledoc false

  alias Jotty.Hermes
  alias Jotty.Tasks.Card

  @spec propose(Path.t(), String.t(), [String.t()], Path.t(), (struct() -> any())) ::
          {:ok, Card.t()} | {:error, term()}
  def propose(hermes, query, history, working_directory, _on_event) do
    options = [toolsets: ["linear"], skills: ["linear-issues"], yolo: false]

    with {:ok, response} <-
           Hermes.run(hermes, prompt(query, history), working_directory, options, fn _event -> :ok end),
         {:ok, payload} when is_map(payload) <- Jason.decode(response),
         {:ok, card} <- Card.from_proposal(payload, List.last(history)) do
      {:ok, card}
    else
      {:error, reason} -> {:error, {:task_proposal, reason}}
      _invalid -> {:error, {:task_proposal, :invalid_response}}
    end
  end

  defp prompt(query, history) do
    """
    Follow the loaded linear-issues skill. Analyze the normalized request using the recent conversation as context.
    Search Linear before proposing anything. This is a READ-ONLY analysis turn: never call a create, update, save,
    archive, delete, or other write-capable tool.

    Return exactly one JSON object, with no markdown fence or prose. All keys are required. Use null when an optional
    value is absent.

    {
      "kind": "existing" | "create" | "update",
      "issue_id": string | null,
      "identifier": string | null,
      "url": string | null,
      "title": string,
      "description": string,
      "team": string,
      "project": string | null,
      "issue_status": string,
      "assignee": string | null,
      "priority": 0 | 1 | 2 | 3 | 4,
      "estimate": number | null,
      "cycle_id": string | null,
      "cycle_number": integer | null,
      "labels": [string],
      "changes": [{"field": string, "from": JSON value, "to": JSON value}]
    }

    Use "existing" only when a matching issue already contains the requested information; its changes must be [].
    Use "create" only when no matching issue exists; issue_id, identifier, and url must be null and changes must be [].
    Use "update" when a matching issue needs changes; include its IDs and list every changed field with current and
    proposed values. The top-level fields must show the complete proposed issue after those changes.

    Resolve every Linear ID to its human-readable companion. For cycle, return both the exact cycle ID required for
    mutation and its integer cycle number. Never put a UUID in cycle_number. Preserve the issue description as
    Markdown, but do not add conversational, Soniox, prompt, or tool-result wrappers around issue content.
    For a cycle change, use human-readable cycle numbers in changes.from and changes.to; use cycle_id only in the
    top-level immutable target.

    Normalized request:
    #{query}

    Recent completed utterances:
    #{Enum.map_join(history, "\n", &"- #{&1}")}
    """
  end
end
