defmodule Jotty.Desktop.RouterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Jotty.Desktop.Router
  alias Jotty.{Recording, Repo}
  alias Jotty.Sessions.{Catalog, Recordings, Session, SessionContext, TranscriptChunk}

  setup do
    Repo.delete_all(TranscriptChunk)
    Repo.delete_all(SessionContext)
    Repo.delete_all(Session)
    :ok
  end

  test "serves a loopback health endpoint" do
    conn = Router.call(conn(:get, "/health"), Router.init([]))
    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  @tag :tmp_dir
  test "streams full playback and normal, suffix, and open-ended byte ranges", %{tmp_dir: home} do
    {id, path} = playable_session(home, "0123456789")

    full = request("/sessions/#{id}/audio")
    assert full.status == 200
    assert full.resp_body == "0123456789"
    assert get_resp_header(full, "content-type") == ["audio/mp4"]
    assert get_resp_header(full, "accept-ranges") == ["bytes"]

    assert_range(id, "bytes=2-5", 206, "2345", "bytes 2-5/10")
    assert_range(id, "bytes=-3", 206, "789", "bytes 7-9/10")
    assert_range(id, "bytes=7-", 206, "789", "bytes 7-9/10")
    assert path == elem(Catalog.playback_path(id), 1)
  end

  @tag :tmp_dir
  test "returns 416 for malformed and unsatisfiable ranges", %{tmp_dir: home} do
    {id, _path} = playable_session(home, "0123456789")

    for range <- [
          "items=0-1",
          "bytes=nope",
          "bytes=10-20",
          "bytes=4-2",
          "bytes=0-1,3-4",
          "bytes=+1-2",
          "bytes=1-+2",
          "bytes=-+3"
        ] do
      response = request("/sessions/#{id}/audio", range)
      assert response.status == 416
      assert get_resp_header(response, "content-range") == ["bytes */10"]
    end
  end

  test "does not accept paths or unknown ids" do
    assert request("/sessions/../../etc/passwd/audio").status == 404
    assert request("/sessions/4b119ce6-d02b-41f7-9368-433f59db56a7/audio").status == 404
  end

  @tag :tmp_dir
  test "returns 404 when the catalog row has no playable artifact", %{tmp_dir: home} do
    recording = Recording.create!(home, DateTime.utc_now())
    Recordings.create!(recording, DateTime.utc_now(), [])
    assert request("/sessions/#{Path.basename(recording.directory)}/audio").status == 404
  end

  defp request(path, range \\ nil) do
    conn = conn(:get, path)
    conn = if range, do: put_req_header(conn, "range", range), else: conn
    Router.call(conn, Router.init([]))
  end

  defp assert_range(id, range, status, body, content_range) do
    response = request("/sessions/#{id}/audio", range)
    assert response.status == status
    assert response.resp_body == body
    assert get_resp_header(response, "content-range") == [content_range]
  end

  defp playable_session(home, contents) do
    started_at = DateTime.utc_now()
    recording = Recording.create!(home, started_at)
    Recordings.create!(recording, started_at, [])
    File.write!(recording.playback_audio, contents)
    {Path.basename(recording.directory), recording.playback_audio}
  end
end
