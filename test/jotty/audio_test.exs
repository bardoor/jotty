defmodule Jotty.AudioTest do
  use ExUnit.Case, async: true

  alias Jotty.Audio

  @tag :tmp_dir
  test "mixes the system and microphone tracks into one mono AAC file", %{tmp_dir: directory} do
    system_audio = Path.join(directory, "system.m4a")
    microphone_audio = Path.join(directory, "microphone.m4a")
    mixed_audio = Path.join(directory, "audio.m4a")

    create_tone!(system_audio, 440)
    create_tone!(microphone_audio, 880)

    assert :ok = Audio.mix(system_audio, microphone_audio, mixed_audio)

    {probe, 0} =
      System.cmd("ffprobe", [
        "-v",
        "error",
        "-select_streams",
        "a:0",
        "-show_entries",
        "stream=codec_name,sample_rate,channels",
        "-of",
        "json",
        mixed_audio
      ])

    assert %{
             "streams" => [
               %{"channels" => 1, "codec_name" => "aac", "sample_rate" => "16000"}
             ]
           } = Jason.decode!(probe)
  end

  defp create_tone!(path, frequency) do
    {_output, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-v",
          "error",
          "-f",
          "lavfi",
          "-i",
          "sine=frequency=#{frequency}:duration=0.1",
          "-c:a",
          "aac",
          path
        ],
        stderr_to_stdout: true
      )
  end
end
