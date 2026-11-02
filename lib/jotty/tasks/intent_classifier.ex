defmodule Jotty.Tasks.IntentClassifier do
  @moduledoc false

  alias Jotty.Hermes
  alias Jotty.Tasks.Card

  @spec classify(Path.t(), [String.t()], [Card.t()], Path.t(), (struct() -> any())) ::
          :ignore | {:inspect_linear, String.t()} | {:error, term()}
  def classify(hermes, history, cards, working_directory, _on_event) do
    options = [toolsets: [], skills: [], yolo: false]

    with {:ok, response} <-
           Hermes.run(hermes, prompt(history, cards), working_directory, options, fn _event -> :ok end),
         {:ok, payload} <- Jason.decode(response) do
      classification(payload)
    else
      {:error, reason} -> {:error, {:task_classification, reason}}
      _invalid -> {:error, {:task_classification, :invalid_response}}
    end
  end

  defp classification(%{"action" => "ignore", "query" => nil}), do: :ignore

  defp classification(%{"action" => "inspect_linear", "query" => query})
       when is_binary(query) and query != "",
       do: {:inspect_linear, query}

  defp classification(_payload), do: {:error, {:task_classification, :invalid_response}}

  defp prompt(history, cards) do
    """
    Decide whether only the latest completed utterance introduces a new request to find, create, or change a Linear
    issue. Use older utterances only to resolve references in that latest utterance. Never reclassify an older request
    because the latest utterance is a follow-up, confirmation, correction, or unrelated speech.

    The visible task requests below include work already being searched or already analyzed. If the latest utterance
    asks for work that is already represented there, return ignore. This includes a paraphrase, continuation, or
    confirmation of an existing request. A status, priority, assignee, cycle, label, title, or description change is
    actionable only when it is a genuinely new request. General discussion without a concrete task action is not.

    Return exactly one JSON object, with no markdown fence or prose:
    {"action":"ignore","query":null}
    or
    {"action":"inspect_linear","query":"concise standalone Linear search request"}

    Recent completed utterances, oldest first:
    #{Enum.map_join(history, "\n", &"- #{&1}")}

    Visible task requests:
    #{Jason.encode!(Enum.map(cards, &visible_card/1))}
    """
  end

  defp visible_card(card) do
    %{
      kind: card.kind,
      status: card.status,
      identifier: card.identifier,
      title: card.title,
      trigger: card.trigger,
      changes: Enum.map(card.changes, fn change -> %{field: change.field, from: change.from, to: change.to} end)
    }
  end
end
