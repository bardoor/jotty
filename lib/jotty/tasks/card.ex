defmodule Jotty.Tasks.Card do
  @moduledoc false

  alias Jotty.Tasks.Change

  @type kind :: :existing | :create | :update
  @type status :: :pending | :applying | :acknowledged | :applied | :denied | :failed | :stale

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          kind: kind(),
          status: status(),
          issue_id: String.t() | nil,
          identifier: String.t() | nil,
          url: String.t() | nil,
          title: String.t(),
          description: String.t(),
          team: String.t(),
          project: String.t() | nil,
          issue_status: String.t(),
          assignee: String.t() | nil,
          priority: non_neg_integer(),
          estimate: number() | nil,
          cycle_id: String.t() | nil,
          cycle_number: non_neg_integer() | nil,
          labels: [String.t()],
          changes: [Change.t()],
          trigger: String.t(),
          error: String.t() | nil
        }

  @enforce_keys ~w(id kind status title description team issue_status priority labels changes trigger)a
  defstruct id: nil,
            kind: nil,
            status: nil,
            issue_id: nil,
            identifier: nil,
            url: nil,
            title: nil,
            description: nil,
            team: nil,
            project: nil,
            issue_status: nil,
            assignee: nil,
            priority: nil,
            estimate: nil,
            cycle_id: nil,
            cycle_number: nil,
            labels: nil,
            changes: nil,
            trigger: nil,
            error: nil

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = card) do
    %{
      id: card.id,
      kind: card.kind,
      status: card.status,
      issue_id: card.issue_id,
      identifier: card.identifier,
      url: card.url,
      title: card.title,
      description: card.description,
      team: card.team,
      project: card.project,
      issue_status: card.issue_status,
      assignee: card.assignee,
      priority: card.priority,
      estimate: card.estimate,
      cycle_id: card.cycle_id,
      cycle_number: card.cycle_number,
      labels: card.labels,
      changes: Enum.map(card.changes, &Change.to_map/1),
      trigger: card.trigger,
      error: card.error
    }
  end

  @spec from_proposal(map(), String.t()) :: {:ok, t()} | {:error, :invalid_task_proposal}
  def from_proposal(
        %{
          "kind" => kind,
          "issue_id" => issue_id,
          "identifier" => identifier,
          "url" => url,
          "title" => title,
          "description" => description,
          "team" => team,
          "project" => project,
          "issue_status" => issue_status,
          "assignee" => assignee,
          "priority" => priority,
          "estimate" => estimate,
          "cycle_id" => cycle_id,
          "cycle_number" => cycle_number,
          "labels" => labels,
          "changes" => changes
        },
        trigger
      )
      when kind in ~w(existing create update) and is_binary(title) and is_binary(description) and
             is_binary(team) and is_binary(issue_status) and is_integer(priority) and priority in 0..4 and
             (is_nil(cycle_id) or is_binary(cycle_id)) and
             (is_nil(cycle_number) or is_integer(cycle_number)) and is_list(labels) and is_list(changes) and
             is_binary(trigger) do
    with {:ok, changes} <- changes(changes),
         :ok <- validate_shape(kind, issue_id, changes) do
      {:ok,
       %__MODULE__{
         id: Ecto.UUID.generate(),
         kind: kind(kind),
         status: initial_status(kind),
         issue_id: issue_id,
         identifier: identifier,
         url: url,
         title: title,
         description: description,
         team: team,
         project: project,
         issue_status: issue_status,
         assignee: assignee,
         priority: priority,
         estimate: estimate,
         cycle_id: cycle_id,
         cycle_number: cycle_number,
         labels: labels,
         changes: changes,
         trigger: trigger,
         error: nil
       }}
    end
  end

  def from_proposal(_payload, _trigger), do: {:error, :invalid_task_proposal}

  @spec apply_result(t(), map()) ::
          {:ok, t()} | {:error, :invalid_task_result | :task_result_mismatch}
  def apply_result(%__MODULE__{kind: :update} = card, %{"outcome" => "stale"}) do
    {:ok, %{card | status: :stale, error: nil}}
  end

  def apply_result(
        %__MODULE__{} = card,
        %{"outcome" => "applied", "issue" => issue}
      )
      when is_map(issue) do
    with {:ok, result} <- verified_issue(issue),
         true <- matches_approved?(card, result) do
      {:ok, struct!(card, Map.merge(result, %{status: :applied, error: nil}))}
    else
      false -> {:error, :task_result_mismatch}
      :error -> {:error, :invalid_task_result}
    end
  end

  def apply_result(_card, _payload), do: {:error, :invalid_task_result}

  @spec from_map(map()) :: t()
  def from_map(payload) do
    %__MODULE__{
      id: payload["id"],
      kind: kind(payload["kind"]),
      status: status(payload["status"]),
      issue_id: payload["issue_id"],
      identifier: payload["identifier"],
      url: payload["url"],
      title: payload["title"],
      description: payload["description"],
      team: payload["team"],
      project: payload["project"],
      issue_status: payload["issue_status"],
      assignee: payload["assignee"],
      priority: payload["priority"],
      estimate: payload["estimate"],
      cycle_id: payload["cycle_id"],
      cycle_number: payload["cycle_number"],
      labels: payload["labels"],
      changes: Enum.map(payload["changes"], &Change.from_map/1),
      trigger: payload["trigger"],
      error: payload["error"]
    }
  end

  defp kind("existing"), do: :existing
  defp kind("create"), do: :create
  defp kind("update"), do: :update

  defp status("pending"), do: :pending
  defp status("applying"), do: :applying
  defp status("acknowledged"), do: :acknowledged
  defp status("applied"), do: :applied
  defp status("denied"), do: :denied
  defp status("failed"), do: :failed
  defp status("stale"), do: :stale

  defp initial_status("existing"), do: :acknowledged
  defp initial_status(_kind), do: :pending

  defp verified_issue(%{
         "issue_id" => issue_id,
         "identifier" => identifier,
         "url" => url,
         "title" => title,
         "description" => description,
         "team" => team,
         "project" => project,
         "issue_status" => issue_status,
         "assignee" => assignee,
         "priority" => priority,
         "estimate" => estimate,
         "cycle_id" => cycle_id,
         "cycle_number" => cycle_number,
         "labels" => labels
       })
       when is_binary(issue_id) and is_binary(identifier) and is_binary(url) and is_binary(title) and
              is_binary(description) and is_binary(team) and is_binary(issue_status) and is_integer(priority) and
              priority in 0..4 and (is_nil(cycle_id) or is_binary(cycle_id)) and
              (is_nil(cycle_number) or is_integer(cycle_number)) and is_list(labels) do
    {:ok,
     %{
       issue_id: issue_id,
       identifier: identifier,
       url: url,
       title: title,
       description: description,
       team: team,
       project: project,
       issue_status: issue_status,
       assignee: assignee,
       priority: priority,
       estimate: estimate,
       cycle_id: cycle_id,
       cycle_number: cycle_number,
       labels: labels
     }}
  end

  defp verified_issue(_payload), do: :error

  defp matches_approved?(card, result) do
    target_matches? = card.kind == :create or result.issue_id == card.issue_id

    target_matches? and
      result.title == card.title and
      result.description == card.description and
      result.team == card.team and
      result.project == card.project and
      result.issue_status == card.issue_status and
      result.assignee == card.assignee and
      result.priority == card.priority and
      result.estimate == card.estimate and
      result.cycle_id == card.cycle_id and
      result.cycle_number == card.cycle_number and
      Enum.sort(result.labels) == Enum.sort(card.labels)
  end

  defp changes(payloads) do
    Enum.reduce_while(payloads, {:ok, []}, fn payload, {:ok, changes} ->
      try do
        {:cont, {:ok, changes ++ [Change.from_map(payload)]}}
      rescue
        FunctionClauseError -> {:halt, {:error, :invalid_task_proposal}}
      end
    end)
  end

  defp validate_shape("create", nil, []), do: :ok
  defp validate_shape("existing", issue_id, []) when is_binary(issue_id), do: :ok
  defp validate_shape("update", issue_id, [_change | _changes]) when is_binary(issue_id), do: :ok
  defp validate_shape(_kind, _issue_id, _changes), do: {:error, :invalid_task_proposal}
end
