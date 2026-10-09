defmodule Jotty.Sessions.Recordings do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias Jotty.Repo
  alias Jotty.Sessions.{Contexts, Session, Transcript}
  alias Jotty.Settings.ContextSnapshot
  alias Jotty.STT.TranscriptionChunk

  @spec create!(Jotty.Recording.t(), DateTime.t(), [ContextSnapshot.t()]) :: Session.t()
  def create!(recording, started_at, contexts) do
    id = Path.basename(recording.directory)

    attributes = %{
      id: id,
      title: default_title(started_at),
      status: :recording,
      started_at: started_at,
      directory: recording.directory,
      system_audio_path: recording.system_audio,
      microphone_audio_path: recording.microphone_audio,
      aec_microphone_audio_path: recording.aec_microphone_audio,
      playback_audio_path: recording.playback_audio,
      transcript_path: recording.transcript,
      summary_path: recording.summary
    }

    Multi.new()
    |> Multi.insert(:session, Session.create_changeset(%Session{}, attributes))
    |> Contexts.insert_all(id, contexts)
    |> Repo.transact()
    |> created_session!()
  end

  @spec complete(Ecto.UUID.t(), [TranscriptionChunk.t()], DateTime.t()) ::
          {:ok, Session.t()} | {:error, term()}
  def complete(id, chunks, completed_at) do
    transition(id, :completed, chunks, completed_at, nil)
  end

  @spec fail(Ecto.UUID.t(), [TranscriptionChunk.t()], DateTime.t(), term()) ::
          {:ok, Session.t()} | {:error, term()}
  def fail(id, chunks, completed_at, reason) do
    transition(id, :failed, chunks, completed_at, inspect(reason))
  end

  @spec fail_orphaned(DateTime.t()) :: :ok
  def fail_orphaned(completed_at) do
    Session
    |> where([session], session.status == :recording)
    |> Repo.all()
    |> Enum.each(fn session ->
      {:ok, %Session{}} = fail(session.id, [], completed_at, :application_restarted)
    end)
  end

  defp transition(id, status, chunks, completed_at, failure) do
    Repo.transact(fn ->
      session = Repo.get!(Session, id)

      if session.status == :recording do
        apply_transition(session, status, chunks, completed_at, failure)
      else
        {:error, {:invalid_status_transition, session.status, status}}
      end
    end)
  end

  defp apply_transition(session, status, chunks, completed_at, failure) do
    attributes = %{
      status: status,
      failure: failure,
      completed_at: completed_at,
      duration_ms: max(DateTime.diff(completed_at, session.started_at, :millisecond), 0)
    }

    session =
      session
      |> Session.transition_changeset(attributes)
      |> Repo.update!()

    :ok = Transcript.replace(session.id, chunks)
    {:ok, session}
  end

  defp created_session!({:ok, %{session: session}}), do: session
  defp created_session!({:error, _operation, reason, _changes}), do: raise(RuntimeError, inspect(reason))
  defp default_title(started_at), do: Calendar.strftime(started_at, "Recording %Y-%m-%d %H:%M")
end
