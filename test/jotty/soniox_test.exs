defmodule Jotty.SonioxTest do
  use ExUnit.Case, async: false

  alias Jotty.Soniox

  @tag :tmp_dir
  test "uploads, transcribes, renders speakers, and removes remote resources", %{
    tmp_dir: directory
  } do
    audio = Path.join(directory, "audio.m4a")
    File.write!(audio, "audio")
    test_process = self()

    Req.Test.stub(Soniox, fn conn ->
      send(test_process, {conn.method, conn.request_path})

      case {conn.method, conn.request_path} do
        {"POST", "/v1/files"} ->
          Req.Test.json(conn, %{"id" => "file-1"})

        {"POST", "/v1/transcriptions"} ->
          Req.Test.json(conn, %{"id" => "transcription-1"})

        {"GET", "/v1/transcriptions/transcription-1"} ->
          Req.Test.json(conn, %{"status" => "completed"})

        {"GET", "/v1/transcriptions/transcription-1/transcript"} ->
          Req.Test.json(conn, %{
            "tokens" => [
              %{"speaker" => "1", "text" => "Hello"},
              %{"speaker" => "1", "text" => " there"},
              %{"speaker" => "2", "text" => "Hi"}
            ]
          })

        {"DELETE", "/v1/transcriptions/transcription-1"} ->
          Req.Test.text(conn, "")

        {"DELETE", "/v1/files/file-1"} ->
          Req.Test.text(conn, "")
      end
    end)

    assert {:ok, "Speaker 1: Hello there\n\nSpeaker 2: Hi"} =
             Soniox.transcribe(audio, "soniox-key")

    assert_received {"DELETE", "/v1/transcriptions/transcription-1"}
    assert_received {"DELETE", "/v1/files/file-1"}
  end

  @tag :tmp_dir
  test "returns the first Soniox HTTP failure without retrying", %{tmp_dir: directory} do
    audio = Path.join(directory, "audio.m4a")
    File.write!(audio, "audio")

    Req.Test.expect(Soniox, 3, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/files"} ->
          Req.Test.json(conn, %{"id" => "file-1"})

        {"POST", "/v1/transcriptions"} ->
          Req.Test.json(conn, %{"id" => "transcription-1"})

        {"GET", "/v1/transcriptions/transcription-1"} ->
          conn
          |> Plug.Conn.put_status(500)
          |> Req.Test.json(%{"error" => "unavailable"})
      end
    end)

    assert {:error, {:soniox_http, 500, %{"error" => "unavailable"}}} =
             Soniox.transcribe(audio, "soniox-key")
  end

  @tag :tmp_dir
  test "stops polling after the configured timeout", %{tmp_dir: directory} do
    audio = Path.join(directory, "audio.m4a")
    File.write!(audio, "audio")
    original_timeout = Application.fetch_env!(:jotty, :soniox_timeout)
    Application.put_env(:jotty, :soniox_timeout, 0)
    on_exit(fn -> Application.put_env(:jotty, :soniox_timeout, original_timeout) end)

    status_requests = :counters.new(1, [])

    Req.Test.stub(Soniox, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/files"} ->
          Req.Test.json(conn, %{"id" => "file-1"})

        {"POST", "/v1/transcriptions"} ->
          Req.Test.json(conn, %{"id" => "transcription-1"})

        {"GET", "/v1/transcriptions/transcription-1"} ->
          :counters.add(status_requests, 1, 1)

          if :counters.get(status_requests, 1) == 1 do
            Req.Test.json(conn, %{"status" => "processing"})
          else
            Req.Test.json(conn, %{"status" => "completed"})
          end

        {"GET", "/v1/transcriptions/transcription-1/transcript"} ->
          Req.Test.json(conn, %{
            "tokens" => [%{"speaker" => "1", "text" => "Unexpected completion"}]
          })

        {"DELETE", _path} ->
          Req.Test.text(conn, "")
      end
    end)

    assert {:error, :transcription_timeout} = Soniox.transcribe(audio, "soniox-key")
  end
end
