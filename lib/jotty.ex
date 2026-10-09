defmodule Jotty do
  @moduledoc "Runs one event-driven recording session."

  alias Jotty.Recording
  alias Jotty.Session.Events.{RecordingStarted, SessionCompleted, SessionFailed}
  alias Jotty.Session.Server
  alias Jotty.Settings.RecordingConfiguration

  @spec record(Path.t(), Path.t(), String.t(), DateTime.t()) :: {:ok, Recording.t()} | {:error, term()}
  def record(home, recorder_executable, soniox_api_key, recorded_at) do
    record(home, recorder_executable, soniox_api_key, recorded_at, [])
  end

  @spec record(Path.t(), Path.t(), String.t(), DateTime.t(), keyword()) ::
          {:ok, Recording.t()} | {:error, term()}
  def record(home, recorder_executable, soniox_api_key, recorded_at, options) do
    recording = Recording.create!(home, recorded_at)
    external_sink = Keyword.get(options, :event_sink)
    event_sinks = Enum.uniq([self() | List.wrap(external_sink)])

    session_options =
      options
      |> Keyword.get(:session_options, [])
      |> Keyword.merge(
        api_key: soniox_api_key,
        event_sinks: event_sinks,
        recorder: recorder_executable,
        recorder_options: [stop: :message],
        recording: recording
      )

    configuration = %RecordingConfiguration{
      contexts: Keyword.get(options, :contexts, []),
      microphone_device_id: nil
    }

    with {:ok, session} <- Server.start_link(session_options),
         :ok <- Server.start_recording(session, configuration) do
      result = await_result(session, Keyword.get(options, :recorder_stop, :stdio))
      GenServer.stop(session)
      result
    end
  end

  defp await_result(session, stop_mode) do
    receive do
      {:jotty_session_event, %RecordingStarted{}} when stop_mode == :stdio ->
        IO.gets("Press Enter to stop recording.\n")
        :ok = Server.stop_recording(session)
        await_result(session, :message)

      {:jotty_session_event, %RecordingStarted{}} ->
        await_result(session, stop_mode)

      {:jotty_session_event, %SessionCompleted{result: result}} ->
        result

      {:jotty_session_event, %SessionFailed{reason: reason}} ->
        {:error, reason}

      :stop ->
        :ok = Server.stop_recording(session)
        await_result(session, :message)

      {:jotty_session_event, _event} ->
        await_result(session, stop_mode)
    end
  end
end
