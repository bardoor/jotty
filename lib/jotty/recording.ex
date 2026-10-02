defmodule Jotty.Recording do
  @moduledoc """
  Owns the directory and durable artifact paths for one recording.
  """

  @enforce_keys [
    :directory,
    :system_audio,
    :microphone_audio,
    :transcript,
    :summary
  ]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          directory: Path.t(),
          system_audio: Path.t(),
          microphone_audio: Path.t(),
          transcript: Path.t(),
          summary: Path.t()
        }

  @doc """
  Creates the recording directory for the given UTC timestamp.
  """
  @spec create!(Path.t(), DateTime.t()) :: t()
  def create!(home, recorded_at) do
    directory =
      Path.join([
        home,
        ".jotty",
        "recordings",
        Calendar.strftime(recorded_at, "%Y%m%d-%H%M%S")
      ])

    File.mkdir_p!(directory)

    %__MODULE__{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }
  end
end
