defmodule Jotty.SessionsTest do
  use ExUnit.Case, async: false

  alias Jotty.{Recording, Repo}
  alias Jotty.Sessions.{Catalog, Contexts, Recordings, Session, SessionContext, Transcript, TranscriptChunk}
  alias Jotty.Settings.{Context, ContextSnapshot}
  alias Jotty.STT.TranscriptionChunk, as: LiveChunk

  setup do
    Repo.delete_all(TranscriptChunk)
    Repo.delete_all(SessionContext)
    Repo.delete_all(Session)
    Repo.delete_all(Context)
    :ok
  end

  @tag :tmp_dir
  test "persists ordered history, context snapshots, chunks, and status transitions", %{tmp_dir: home} do
    context = Repo.insert!(%Context{name: "Project", path: "/project", position: 0})
    older = create_session(home, ~U[2026-10-03 08:00:00Z], [])
    newer = create_session(home, ~U[2026-10-03 09:00:00Z], [snapshot(context)])

    chunks = [
      %LiveChunk{speaker: "2", text: "Second", start_ms: 20, end_ms: 30},
      %LiveChunk{speaker: "1", text: "First", start_ms: 0, end_ms: 10}
    ]

    File.write!(newer.playback_audio, "audio")
    File.write!(newer.transcript, "canonical")
    File.write!(newer.summary, "# Summary")

    assert {:ok, completed} =
             Recordings.complete(Path.basename(newer.directory), chunks, ~U[2026-10-03 09:01:00Z])

    assert completed.status == :completed
    assert completed.duration_ms == 60_000
    assert Enum.map(Catalog.all(), & &1.id) == [completed.id, Path.basename(older.directory)]
    assert [%TranscriptChunk{}, %TranscriptChunk{}] = Transcript.all(completed.id)
    assert [%SessionContext{}] = Contexts.all(completed.id)

    assert {:ok, opened} = Catalog.open(completed.id, "http://127.0.0.1:4765")
    assert Enum.map(opened.transcript_chunks, & &1.text) == ["Second", "First"]
    assert opened.summary_markdown == "# Summary"
    assert opened.playback_url == "http://127.0.0.1:4765/sessions/#{completed.id}/audio"
    assert [%{name: "Project", path: "/project"}] = opened.contexts

    assert {:error, {:invalid_status_transition, :completed, :failed}} =
             Recordings.fail(completed.id, [], ~U[2026-10-03 09:02:00Z], :late_failure)

    Repo.delete!(context)
    assert {:ok, opened} = Catalog.open(completed.id, "http://localhost")
    assert [%{context_id: nil, name: "Project", path: "/project"}] = opened.contexts
  end

  @tag :tmp_dir
  test "renames metadata without moving files and validates bounded nonblank titles", %{tmp_dir: home} do
    recording = create_session(home, ~U[2026-10-03 09:00:00Z], [])
    id = Path.basename(recording.directory)

    assert {:ok, renamed} = Catalog.rename(id, "  Planning  ")
    assert renamed.title == "Planning"
    assert Repo.get!(Session, id).directory == recording.directory
    assert {:error, changeset} = Catalog.rename(id, "   ")
    assert "can't be blank" in errors_on(changeset).title
    assert {:error, changeset} = Catalog.rename(id, String.duplicate("x", 121))
    assert "should be at most 120 character(s)" in errors_on(changeset).title
  end

  @tag :tmp_dir
  test "failed sessions remain open with honest missing artifact states", %{tmp_dir: home} do
    recording = create_session(home, ~U[2026-10-03 09:00:00Z], [])
    id = Path.basename(recording.directory)
    assert {:ok, failed} = Recordings.fail(id, [], ~U[2026-10-03 09:00:01Z], :capture_failed)
    assert failed.status == :failed

    assert {:ok, opened} = Catalog.open(id, "http://localhost")
    refute opened.transcript_available
    assert opened.summary_markdown == nil
    assert opened.playback_url == nil
  end

  @tag :tmp_dir
  test "deletes owned data and rejects corrupted out-of-root directories", %{tmp_dir: home} do
    recording = create_session(home, ~U[2026-10-03 09:00:00Z], [])
    id = Path.basename(recording.directory)
    root = Path.join([home, ".jotty", "recordings"])
    assert :ok = Catalog.delete(id, root)
    refute File.exists?(recording.directory)
    assert Repo.get(Session, id) == nil

    unsafe = create_session(home, ~U[2026-10-03 10:00:00Z], [])
    unsafe_id = Path.basename(unsafe.directory)
    session = Repo.get!(Session, unsafe_id)

    session
    |> Ecto.Changeset.change(directory: home)
    |> Repo.update!()

    assert {:error, :unsafe_recording_directory} = Catalog.delete(unsafe_id, root)
    assert File.dir?(home)
  end

  defp create_session(home, started_at, contexts) do
    recording = Recording.create!(home, started_at)
    Recordings.create!(recording, started_at, contexts)
    recording
  end

  defp snapshot(context) do
    %ContextSnapshot{
      id: context.id,
      name: context.name,
      path: context.path,
      position: context.position,
      available: true
    }
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        to_string(Keyword.get(options, String.to_existing_atom(key), key))
      end)
    end)
  end
end
