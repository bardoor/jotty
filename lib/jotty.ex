defmodule Jotty do
  @moduledoc """
  Runs the complete local recording, transcription, and summary workflow.
  """

  alias Jotty.{Assistant, Audio, Recorder, Recording, Session, Soniox, Summarizer}

  @doc """
  Processes one recording sequentially and leaves every completed local artifact
  in its timestamped directory if a later stage fails.
  """
  @spec record(Path.t(), Path.t(), String.t(), DateTime.t()) ::
          {:ok, Recording.t()} | {:error, term()}
  def record(home, recorder_executable, soniox_api_key, recorded_at) do
    record(home, recorder_executable, soniox_api_key, recorded_at, [])
  end

  @spec record(Path.t(), Path.t(), String.t(), DateTime.t(), keyword()) ::
          {:ok, Recording.t()} | {:error, term()}
  def record(home, recorder_executable, soniox_api_key, recorded_at, options) do
    recording = Recording.create!(home, recorded_at)
    contexts = Keyword.get(options, :contexts, [])
    session_options = Keyword.get(options, :session_options, [])
    realtime? = Keyword.get(options, :realtime, contexts != [])

    if realtime? do
      session_options = Keyword.put(session_options, :event_sink, Keyword.get(options, :event_sink))
      recorder_options = [stop: Keyword.get(options, :recorder_stop, :stdio)]

      execute_realtime_recording(
        recording,
        recorder_executable,
        soniox_api_key,
        contexts,
        session_options,
        recorder_options
      )
    else
      execute_recording(recording, recorder_executable, soniox_api_key)
    end
  end

  defp execute_recording(recording, recorder_executable, soniox_api_key) do
    result = Recorder.record(recorder_executable, recording.directory)
    post_process(result, recording, soniox_api_key)
  end

  defp execute_realtime_recording(
         recording,
         recorder_executable,
         soniox_api_key,
         contexts,
         session_options,
         recorder_options
       ) do
    assistant = start_assistant(recording.directory, contexts)

    record_realtime(
      assistant,
      recording,
      recorder_executable,
      soniox_api_key,
      session_options,
      recorder_options
    )
  end

  defp record_realtime(
         {:ok, assistant},
         recording,
         recorder_executable,
         soniox_api_key,
         session_options,
         recorder_options
       ) do
    options = Keyword.merge(session_options, api_key: soniox_api_key, assistant: assistant)
    session = Session.start(options)

    record_live(
      session,
      assistant,
      recording,
      recorder_executable,
      soniox_api_key,
      recorder_options
    )
  end

  defp record_realtime(
         {:error, reason},
         _recording,
         _recorder,
         _api_key,
         _session_options,
         _recorder_options
       ) do
    {:error, reason}
  end

  defp record_live(
         {:error, reason},
         assistant,
         _recording,
         _recorder,
         _api_key,
         _recorder_options
       ) do
    disable_assistant(assistant)
    {:error, reason}
  end

  defp record_live(
         {:ok, session},
         _assistant,
         recording,
         recorder,
         api_key,
         recorder_options
       ) do
    result = Session.record(recorder, recording.directory, session, recorder_options)
    post_process(result, recording, api_key)
  end

  defp start_assistant(_directory, []), do: {:ok, nil}
  defp start_assistant(directory, contexts), do: Assistant.start(directory, contexts)

  defp disable_assistant(nil), do: :ok
  defp disable_assistant(assistant), do: Assistant.disable(assistant)

  defp post_process({:error, reason}, _recording, _soniox_api_key), do: {:error, reason}

  defp post_process(:ok, recording, soniox_api_key) do
    mixed = Audio.mix(recording.system_audio, recording.microphone_audio, recording.mixed_audio)

    with :ok <- mixed,
         {:ok, transcript} <- Soniox.transcribe(recording.mixed_audio, soniox_api_key),
         :ok <- File.write(recording.transcript, transcript),
         :ok <- Summarizer.summarize(recording.transcript, recording.summary) do
      {:ok, recording}
    end
  end
end
