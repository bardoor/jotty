defmodule Jotty.Settings.Context do
  @moduledoc false

  use Jotty.Model

  @required_fields ~w(name path position)a
  @optional_fields ~w()a

  schema "contexts" do
    field :name, :string
    field :path, :string
    field :position, :integer

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(context, attributes) do
    context
    |> cast(attributes, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:path)
  end
end
