defmodule Jotty.Settings.Preferences do
  @moduledoc false

  alias Jotty.Repo
  alias Jotty.Settings.Setting

  @spec get!() :: Setting.t()
  def get!, do: Repo.one!(Setting)

  @spec change_always_on_top(boolean()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def change_always_on_top(enabled) when is_boolean(enabled) do
    update(%{always_on_top: enabled})
  end

  @spec change_microphone(String.t() | nil) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def change_microphone(device_id) when is_binary(device_id) or is_nil(device_id) do
    update(%{microphone_device_id: device_id})
  end

  defp update(attributes) do
    Setting
    |> Repo.one!()
    |> Setting.changeset(attributes)
    |> Repo.update()
  end
end
