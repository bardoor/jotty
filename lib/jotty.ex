defmodule Jotty do
  @moduledoc """
  Runs the complete local recording, transcription, and summary workflow.
  """

  alias Jotty.{Audio, Recorder, Recording, Soniox, Summarizer}

  @doc """
  Processes one recording sequentially and leaves every completed local artifact
  in its timestamped directory if a later stage fails.
  """
  @spec record(Path.t(), Path.t(), String.t(), DateTime.t()) ::
          {:ok, Recording.t()} | {:error, term()}
  def record(home, recorder_executable, soniox_api_key, recorded_at) do
    recording = Recording.create!(home, recorded_at)

    with :ok <- Recorder.record(recorder_executable, recording.directory),
         :ok <-
           Audio.mix(recording.system_audio, recording.microphone_audio, recording.mixed_audio),
         {:ok, transcript} <- Soniox.transcribe(recording.mixed_audio, soniox_api_key),
         :ok <- File.write(recording.transcript, transcript),
         :ok <- Summarizer.summarize(recording.transcript, recording.summary) do
      {:ok, recording}
    end
  end
end
