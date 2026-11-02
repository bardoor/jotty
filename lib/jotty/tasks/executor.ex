defmodule Jotty.Tasks.Executor do
  @moduledoc false

  alias Jotty.Hermes
  alias Jotty.Tasks.Card

  @spec apply(Path.t(), Card.t(), Path.t(), (struct() -> any())) ::
          {:ok, Card.t()} | {:error, term()}
  def apply(hermes, %Card{} = card, working_directory, _on_event) do
    options = [toolsets: ["linear"], skills: ["linear-issues"], yolo: true]

    with {:ok, response} <- Hermes.run(hermes, prompt(card), working_directory, options, fn _event -> :ok end),
         {:ok, payload} when is_map(payload) <- Jason.decode(response),
         {:ok, applied} <- Card.apply_result(card, payload) do
      {:ok, applied}
    else
      {:error, reason} -> {:error, {:task_mutation, reason}}
      _invalid -> {:error, {:task_mutation, :invalid_response}}
    end
  end

  defp prompt(card) do
    """
    Follow the loaded linear-issues skill. The user explicitly approved the immutable task proposal below.
    Execute exactly this one create or update operation. Do not infer, add, or change any field outside the proposal.
    For an update, first read the issue and abort without writing if any listed current value no longer matches.
    After writing, read the issue back and return its verified state.

    Approved proposal:
    #{Jason.encode!(Card.to_map(card))}

    If the update is stale, return exactly {"outcome":"stale"} and do not write.
    Otherwise return exactly one JSON object, with no markdown fence or prose, using this shape:
    {
      "outcome": "applied",
      "issue": {
        "issue_id": string,
        "identifier": string,
        "url": string,
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
        "labels": [string]
      }
    }
    """
  end
end
