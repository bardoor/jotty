defmodule Jotty.Desktop.Socket do
  @moduledoc false

  @behaviour WebSock

  require Logger

  alias Jotty.Desktop.Commands.{
    AddContext,
    ChangeAlwaysOnTop,
    ChangeMicrophone,
    DeleteSession,
    ListMicrophones,
    ListSessions,
    OpenSession,
    RemoveContext,
    RenameSession,
    ReorderContexts,
    StartSession,
    StopSession
  }

  alias Jotty.Desktop.{ContextApproval, Controller, Protocol}
  alias Jotty.Desktop.Events.{CommandRejected, SettingsChanged}
  alias Jotty.{Recorder, Settings}

  @impl WebSock
  def init(%{controller: controller, recorder: recorder, context_approval_secret: approval_secret}) do
    Logger.metadata(controller_id: inspect(controller))
    Logger.info("connected", scope: :desktop)
    snapshot = Controller.attach(controller, self())
    {microphones, microphone_error} = load_microphones(recorder)

    state = %{
      controller: controller,
      recorder: recorder,
      microphones: microphones,
      microphone_error: microphone_error,
      context_approval_secret: approval_secret
    }

    send(self(), :send_settings)
    {:push, {:text, Protocol.encode_event(snapshot)}, state}
  end

  @impl WebSock
  def handle_in({payload, opcode: :text}, state) do
    case decode(payload) do
      {:ok, command} -> run(command, state)
      {:error, reason} -> push_error(reason, state)
    end
  end

  @impl WebSock
  def handle_info(:send_settings, state), do: push_settings(state)

  def handle_info({:EXIT, port, _reason}, state) when is_port(port), do: {:ok, state}

  def handle_info({:jotty_desktop_event, event}, state) do
    {:push, {:text, Protocol.encode_event(event)}, state}
  end

  @impl WebSock
  def terminate(reason, _state) do
    Logger.info("disconnected", scope: :desktop, reason: inspect(reason))
  end

  defp run(%command_struct{} = command, state)
       when command_struct in [
              StartSession,
              StopSession,
              ListSessions,
              OpenSession,
              RenameSession,
              DeleteSession
            ] do
    case Controller.command(state.controller, command) do
      :ok -> {:ok, state}
      {:event, event} -> {:push, {:text, Protocol.encode_event(event)}, state}
    end
  end

  defp run(%ChangeAlwaysOnTop{enabled: enabled}, state) do
    update_settings(Settings.change_always_on_top(enabled), state)
  end

  defp run(%ChangeMicrophone{microphone_device_id: device_id}, state) do
    update_settings(Settings.change_microphone(device_id), state)
  end

  defp run(%AddContext{path: path, approval: approval}, state) do
    if ContextApproval.valid?(state.context_approval_secret, path, approval) do
      update_settings(Settings.add_context(path), state)
    else
      push_settings(state, "Context folder was not approved by the directory picker")
    end
  end

  defp run(%RemoveContext{id: id}, state), do: update_settings(Settings.remove_context(id), state)

  defp run(%ReorderContexts{context_ids: ids}, state),
    do: update_settings(Settings.reorder_contexts(ids), state)

  defp run(%ListMicrophones{}, state) do
    {microphones, microphone_error} = load_microphones(state.recorder)
    push_settings(%{state | microphones: microphones, microphone_error: microphone_error})
  end

  defp update_settings({:ok, _value}, state), do: push_settings(state)
  defp update_settings(:ok, state), do: push_settings(state)
  defp update_settings({:error, reason}, state), do: push_settings(state, format_settings_error(reason))

  defp push_settings(state, error \\ nil) do
    event = %SettingsChanged{
      snapshot: Settings.snapshot(state.microphones),
      error: error || state.microphone_error
    }

    {:push, {:text, Protocol.encode_event(event)}, state}
  end

  defp push_error(reason, state) do
    event = %CommandRejected{command: :invalid, reason: reason}
    {:push, {:text, Protocol.encode_event(event)}, state}
  end

  defp decode(payload) do
    {:ok, Protocol.decode!(payload)}
  rescue
    error in [Jason.DecodeError, ArgumentError, FunctionClauseError] ->
      {:error, "Invalid command: #{Exception.message(error)}"}
  end

  defp load_microphones(recorder) do
    case Recorder.list_microphones(recorder) do
      {:ok, microphones} -> {microphones, nil}
      {:error, reason} -> {[], "Could not list microphones: #{inspect(reason)}"}
    end
  end

  defp format_settings_error({:microphone_device_unavailable, device_id}) do
    "Selected microphone is unavailable: #{device_id}"
  end

  defp format_settings_error({:context_directory_not_found, path}) do
    "Context folder is unavailable: #{path}"
  end

  defp format_settings_error(%Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _options} -> message end)
    inspect(errors)
  end

  defp format_settings_error(reason), do: inspect(reason)
end
