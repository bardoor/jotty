defmodule JottyTest do
  use ExUnit.Case, async: false

  alias Jotty.Recording

  @tag :tmp_dir
  test "records, mixes, transcribes, and summarizes one call", %{tmp_dir: home} do
    recorder = fake_recorder!(home)
    fake_codex!(home)
    stub_soniox()

    assert {:ok, %Recording{} = recording} =
             Jotty.record(home, recorder, "soniox-key", ~U[2026-09-21 17:45:00Z])

    assert File.exists?(recording.system_audio)
    assert File.exists?(recording.microphone_audio)
    assert File.exists?(recording.mixed_audio)
    assert File.read!(recording.transcript) == "Speaker 1: We approved the release."
    assert File.read!(recording.summary) == "# Summary\nRelease approved.\n"
  end

  defp stub_soniox do
    Req.Test.stub(Jotty.Soniox, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/files"} ->
          Req.Test.json(conn, %{"id" => "file-1"})

        {"POST", "/v1/transcriptions"} ->
          Req.Test.json(conn, %{"id" => "transcription-1"})

        {"GET", "/v1/transcriptions/transcription-1"} ->
          Req.Test.json(conn, %{"status" => "completed"})

        {"GET", "/v1/transcriptions/transcription-1/transcript"} ->
          Req.Test.json(conn, %{
            "tokens" => [%{"speaker" => "1", "text" => "We approved the release."}]
          })

        {"DELETE", _path} ->
          Req.Test.text(conn, "")
      end
    end)
  end

  defp fake_recorder!(home) do
    path = Path.join(home, "recorder")

    File.write!(path, """
    #!/bin/sh
    ffmpeg -v error -f lavfi -i sine=frequency=440:duration=0.1 -c:a aac "$1/system.m4a"
    ffmpeg -v error -f lavfi -i sine=frequency=880:duration=0.1 -c:a aac "$1/microphone.m4a"
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp fake_codex!(home) do
    bin_directory = Path.join(home, "bin")
    path = Path.join(bin_directory, "codex")
    File.mkdir!(bin_directory)

    File.write!(path, """
    #!/bin/sh
    output=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output-last-message" ]; then
        shift
        output="$1"
      fi
      shift
    done
    /bin/cat >/dev/null
    /usr/bin/printf '# Summary\nRelease approved.\n' > "$output"
    """)

    File.chmod!(path, 0o755)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    on_exit(fn -> System.put_env("PATH", original_path) end)
  end
end
