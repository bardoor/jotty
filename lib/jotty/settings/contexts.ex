defmodule Jotty.Settings.Contexts do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias Jotty.Repo
  alias Jotty.Settings.{Context, ContextSnapshot}

  @spec all() :: [ContextSnapshot.t()]
  def all do
    Context
    |> order_by([context], asc: context.position, asc: context.id)
    |> Repo.all()
    |> Enum.map(&snapshot/1)
  end

  @spec add(Path.t()) :: {:ok, Context.t()} | {:error, term()}
  def add(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    if File.dir?(expanded_path) do
      Repo.transact(fn ->
        position =
          Context
          |> select([context], max(context.position))
          |> Repo.one()

        position = position || -1

        attributes = %{
          name: Path.basename(expanded_path),
          path: expanded_path,
          position: position + 1
        }

        %Context{}
        |> Context.changeset(attributes)
        |> Repo.insert()
      end)
    else
      {:error, {:context_directory_not_found, expanded_path}}
    end
  end

  @spec remove(Ecto.UUID.t()) :: :ok | {:error, :context_not_found}
  def remove(id) when is_binary(id) do
    case Repo.transact(fn -> remove_and_compact(id) end) do
      {:ok, :ok} -> :ok
      {:error, :context_not_found} -> {:error, :context_not_found}
    end
  end

  @spec reorder([Ecto.UUID.t()]) :: :ok | {:error, term()}
  def reorder(ids) when is_list(ids) do
    contexts = persisted_contexts()

    if same_ids?(ids, contexts) do
      contexts_by_id = Map.new(contexts, &{&1.id, &1})

      ids
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {id, position}, multi ->
        changeset = Context.changeset(contexts_by_id[id], %{position: position})
        Multi.update(multi, {:context, id}, changeset)
      end)
      |> Repo.transact()
      |> transaction_result()
    else
      {:error, :invalid_context_order}
    end
  end

  defp persisted_contexts do
    Context
    |> order_by([context], asc: context.position, asc: context.id)
    |> Repo.all()
  end

  defp snapshot(context) do
    %ContextSnapshot{
      id: context.id,
      name: context.name,
      path: context.path,
      position: context.position,
      available: File.dir?(context.path)
    }
  end

  defp remove_and_compact(id) do
    case Repo.get(Context, id) do
      nil ->
        {:error, :context_not_found}

      context ->
        Repo.delete!(context)
        compact()
        {:ok, :ok}
    end
  end

  defp compact do
    persisted_contexts()
    |> Enum.with_index()
    |> Enum.each(fn {context, position} ->
      context
      |> Context.changeset(%{position: position})
      |> Repo.update!()
    end)
  end

  defp same_ids?(ids, contexts) do
    Enum.sort(ids) == Enum.sort(Enum.map(contexts, & &1.id)) and length(ids) == length(Enum.uniq(ids))
  end

  defp transaction_result({:ok, _changes}), do: :ok
  defp transaction_result({:error, _operation, reason, _changes}), do: {:error, reason}
end
