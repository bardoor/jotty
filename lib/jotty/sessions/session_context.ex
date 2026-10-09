defmodule Jotty.Sessions.SessionContext do
  @moduledoc false

  use Jotty.Model

  alias Jotty.Sessions.Session
  alias Jotty.Settings.Context, as: GlobalContext

  @required_fields ~w(session_id position name path)a
  @optional_fields ~w(context_id)a

  schema "session_contexts" do
    field :position, :integer
    field :name, :string
    field :path, :string
    belongs_to :session, Session
    belongs_to :context, GlobalContext

    timestamps()
  end

  def changeset(context, attributes) do
    context
    |> cast(attributes, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:context_id)
    |> unique_constraint(~w(session_id position)a)
  end
end
