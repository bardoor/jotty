defmodule Jotty.Audio do
  @moduledoc """
  Mixes the native recorder's two source tracks into the transcription input.
  """

  @doc """
  Mixes system and microphone audio into 16 kHz mono AAC.
  """
  @spec mix(Path.t(), Path.t(), Path.t()) :: :ok | {:error, {:ffmpeg, String.t()}}
  def mix(system_audio, microphone_audio, output) do
    arguments = [
      "-v",
      "error",
      "-y",
      "-i",
      system_audio,
      "-i",
      microphone_audio,
      "-filter_complex",
      "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,alimiter=limit=0.95[a]",
      "-map",
      "[a]",
      "-ac",
      "1",
      "-ar",
      "16000",
      "-c:a",
      "aac",
      "-b:a",
      "32k",
      output
    ]

    case System.cmd("ffmpeg", arguments, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, {:ffmpeg, String.trim(output)}}
    end
  end
end
