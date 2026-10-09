defmodule Jotty.Settings do
  @moduledoc "Persists desktop recording settings and global project contexts."

  alias Jotty.Settings.{Context, Contexts, Microphone, Preferences, RecordingConfiguration, Setting, Snapshot}

  @spec snapshot([Microphone.t()]) :: Snapshot.t()
  def snapshot(microphones \\ []) do
    setting = Preferences.get!()
    microphone_ids = MapSet.new(microphones, & &1.id)

    %Snapshot{
      always_on_top: setting.always_on_top,
      microphone_device_id: setting.microphone_device_id,
      microphone_available:
        setting.microphone_device_id == nil or MapSet.member?(microphone_ids, setting.microphone_device_id),
      microphones: microphones,
      contexts: Contexts.all()
    }
  end

  @spec change_always_on_top(boolean()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def change_always_on_top(enabled) when is_boolean(enabled) do
    Preferences.change_always_on_top(enabled)
  end

  @spec change_microphone(String.t() | nil) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def change_microphone(device_id) when is_binary(device_id) or is_nil(device_id) do
    Preferences.change_microphone(device_id)
  end

  @spec add_context(Path.t()) :: {:ok, Context.t()} | {:error, term()}
  def add_context(path) when is_binary(path) do
    Contexts.add(path)
  end

  @spec remove_context(Ecto.UUID.t()) :: :ok | {:error, :context_not_found}
  def remove_context(id) when is_binary(id) do
    Contexts.remove(id)
  end

  @spec reorder_contexts([Ecto.UUID.t()]) :: :ok | {:error, :invalid_context_order}
  def reorder_contexts(ids) when is_list(ids) do
    Contexts.reorder(ids)
  end

  @spec recording_configuration(Snapshot.t()) ::
          {:ok, RecordingConfiguration.t()} | {:error, term()}
  def recording_configuration(%Snapshot{} = snapshot) do
    cond do
      not snapshot.microphone_available ->
        {:error, {:microphone_device_unavailable, snapshot.microphone_device_id}}

      context = Enum.find(snapshot.contexts, &(not &1.available)) ->
        {:error, {:context_directory_not_found, context.path}}

      true ->
        {:ok,
         %RecordingConfiguration{
           microphone_device_id: snapshot.microphone_device_id,
           contexts: Enum.map(snapshot.contexts, & &1.path)
         }}
    end
  end
end
