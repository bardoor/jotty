defmodule Jotty.Settings.Setting do
  @moduledoc false

  use Jotty.Model

  @required_fields ~w(always_on_top)a
  @optional_fields ~w(microphone_device_id)a

  schema "settings" do
    field :always_on_top, :boolean, default: false
    field :microphone_device_id, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(setting, attributes) do
    setting
    |> cast(attributes, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
