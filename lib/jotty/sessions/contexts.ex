defmodule Jotty.Sessions.Contexts do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias Jotty.Repo
  alias Jotty.Sessions.SessionContext
  alias Jotty.Settings.ContextSnapshot

  @spec insert_all(Multi.t(), Ecto.UUID.t(), [ContextSnapshot.t()]) :: Multi.t()
  def insert_all(multi, session_id, contexts) do
    Enum.reduce(contexts, multi, fn context, multi ->
      attributes = %{
        session_id: session_id,
        context_id: context.id,
        position: context.position,
        name: context.name,
        path: context.path
      }

      changeset = SessionContext.changeset(%SessionContext{}, attributes)
      Multi.insert(multi, {:context, context.position}, changeset)
    end)
  end

  @spec all(Ecto.UUID.t()) :: [SessionContext.t()]
  def all(session_id) do
    SessionContext
    |> where([context], context.session_id == ^session_id)
    |> order_by([context], asc: context.position)
    |> Repo.all()
  end
end
