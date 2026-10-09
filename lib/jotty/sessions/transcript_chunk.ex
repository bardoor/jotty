defmodule Jotty.Sessions.TranscriptChunk do
  @moduledoc false

  use Jotty.Model

  alias Jotty.Sessions.Session

  @required_fields ~w(session_id position speaker text start_ms end_ms)a
  @optional_fields ~w()a

  schema "transcript_chunks" do
    field :position, :integer
    field :speaker, :string
    field :text, :string
    field :start_ms, :integer
    field :end_ms, :integer
    belongs_to :session, Session

    timestamps()
  end

  def changeset(chunk, attributes) do
    chunk
    |> cast(attributes, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:session_id)
    |> unique_constraint(~w(session_id position)a)
  end
end
