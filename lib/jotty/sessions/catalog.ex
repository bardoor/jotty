defmodule Jotty.Sessions.Catalog do
  @moduledoc false

  import Ecto.Query

  alias Jotty.Repo
  alias Jotty.Sessions.{Contexts, Session, Transcript}
  alias Jotty.Tasks.{Card, Store}

  @spec all() :: [map()]
  def all do
    Session
    |> order_by([session], desc: session.started_at, desc: session.id)
    |> Repo.all()
    |> Enum.map(&metadata/1)
  end

  @spec open(Ecto.UUID.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def open(id, audio_base_url) do
    with {:ok, session} <- fetch(id) do
      details = %{
        transcript_chunks: Enum.map(Transcript.all(session.id), &transcript_chunk/1),
        transcript_available: File.regular?(session.transcript_path),
        summary_markdown: read_optional(session.summary_path),
        contexts: Enum.map(Contexts.all(session.id), &context/1),
        task_cards: task_cards(session.directory),
        task_error: nil,
        playback_url: playback_url(session, audio_base_url)
      }

      {:ok, Map.merge(metadata(session), details)}
    end
  end

  @spec rename(Ecto.UUID.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def rename(id, title) do
    with {:ok, session} <- fetch(id),
         {:ok, session} <- update_title(session, title) do
      {:ok, metadata(session)}
    end
  end

  @spec delete(Ecto.UUID.t(), Path.t()) :: :ok | {:error, term()}
  def delete(id, recordings_root) do
    with {:ok, session} <- fetch(id),
         :ok <- validate_owned_directory(session, recordings_root),
         {:ok, quarantine} <- quarantine(session) do
      delete_quarantined(session, quarantine)
    end
  end

  @spec playback_path(Ecto.UUID.t()) :: {:ok, Path.t()} | {:error, :not_found | :not_playable}
  def playback_path(id) do
    with {:ok, session} <- fetch(id) do
      if playable?(session.playback_audio_path) do
        {:ok, session.playback_audio_path}
      else
        {:error, :not_playable}
      end
    end
  end

  defp fetch(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Session{} = session <- Repo.get(Session, id) do
      {:ok, session}
    else
      _reason -> {:error, :not_found}
    end
  end

  defp update_title(session, title) do
    session
    |> Session.rename_changeset(%{title: title})
    |> Repo.update()
  end

  defp quarantine(session) do
    quarantine = session.directory <> ".deleting-" <> Ecto.UUID.generate()

    case File.rename(session.directory, quarantine) do
      :ok -> {:ok, quarantine}
      {:error, reason} -> {:error, {:delete_directory, reason}}
    end
  end

  defp delete_quarantined(session, quarantine) do
    case Repo.delete(session) do
      {:ok, %Session{}} -> remove_quarantine(quarantine)
      {:error, changeset} -> restore_quarantine(quarantine, session.directory, changeset)
    end
  end

  defp remove_quarantine(quarantine) do
    case File.rm_rf(quarantine) do
      {:ok, _paths} -> :ok
      {:error, reason, path} -> {:error, {:cleanup_failed, path, reason}}
    end
  end

  defp restore_quarantine(quarantine, directory, changeset) do
    case File.rename(quarantine, directory) do
      :ok -> {:error, changeset}
      {:error, reason} -> {:error, {:restore_directory, reason, changeset}}
    end
  end

  defp metadata(session) do
    %{
      id: session.id,
      title: session.title,
      status: session.status,
      failure: session.failure,
      started_at: session.started_at,
      completed_at: session.completed_at,
      duration_ms: session.duration_ms
    }
  end

  defp transcript_chunk(chunk) do
    %{
      position: chunk.position,
      speaker: chunk.speaker,
      text: chunk.text,
      start_ms: chunk.start_ms,
      end_ms: chunk.end_ms
    }
  end

  defp context(context) do
    %{
      context_id: context.context_id,
      position: context.position,
      name: context.name,
      path: context.path
    }
  end

  defp read_optional(path) do
    if File.regular?(path), do: File.read!(path), else: nil
  end

  defp task_cards(directory) do
    case Store.read(Path.join(directory, "tasks.json")) do
      {:ok, cards} -> Enum.map(cards, &Card.to_map/1)
      {:error, _reason} -> []
    end
  end

  defp playback_url(session, base_url) do
    if playable?(session.playback_audio_path), do: "#{base_url}/sessions/#{session.id}/audio", else: nil
  end

  defp playable?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> true
      _result -> false
    end
  end

  defp validate_owned_directory(session, recordings_root) do
    root = Path.expand(recordings_root)
    directory = Path.expand(session.directory)
    relative = Path.relative_to(directory, root)

    if Path.dirname(directory) == root and relative == session.id and File.dir?(directory) do
      :ok
    else
      {:error, :unsafe_recording_directory}
    end
  end
end
