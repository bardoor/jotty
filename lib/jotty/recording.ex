defmodule Jotty.Recording do
  @moduledoc """
  Owns the directory and durable artifact paths for one recording.
  """

  @type t() :: %__MODULE__{
          directory: Path.t(),
          system_audio: Path.t(),
          microphone_audio: Path.t(),
          aec_microphone_audio: Path.t(),
          playback_audio: Path.t(),
          transcript: Path.t(),
          summary: Path.t()
        }

  @enforce_keys ~w(directory system_audio microphone_audio transcript summary)a
  defstruct ~w(directory system_audio microphone_audio aec_microphone_audio playback_audio transcript summary)a

  @doc """
  Creates the recording directory for the given UTC timestamp.
  """
  @spec create!(Path.t(), DateTime.t(), Ecto.UUID.t()) :: t()
  def create!(home, _recorded_at, id \\ Ecto.UUID.generate()) do
    directory = Path.join([home, ".jotty", "recordings", id])

    File.mkdir_p!(directory)

    %__MODULE__{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      aec_microphone_audio: Path.join(directory, "microphone-aec.wav"),
      playback_audio: Path.join(directory, "audio.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }
  end
end
