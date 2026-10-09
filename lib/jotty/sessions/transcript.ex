defmodule Jotty.Sessions.Transcript do
  @moduledoc false

  import Ecto.Query

  alias Jotty.Repo
  alias Jotty.Sessions.TranscriptChunk
  alias Jotty.STT.TranscriptionChunk, as: LiveChunk

  @spec all(Ecto.UUID.t()) :: [TranscriptChunk.t()]
  def all(session_id) do
    TranscriptChunk
    |> where([chunk], chunk.session_id == ^session_id)
    |> order_by([chunk], asc: chunk.position)
    |> Repo.all()
  end

  @spec replace(Ecto.UUID.t(), [LiveChunk.t()]) :: :ok
  def replace(session_id, chunks) do
    TranscriptChunk
    |> where([chunk], chunk.session_id == ^session_id)
    |> Repo.delete_all()

    chunks
    |> Enum.with_index()
    |> Enum.each(fn {%LiveChunk{} = chunk, position} ->
      attributes = %{
        session_id: session_id,
        position: position,
        speaker: chunk.speaker,
        text: chunk.text,
        start_ms: chunk.start_ms,
        end_ms: chunk.end_ms
      }

      %TranscriptChunk{}
      |> TranscriptChunk.changeset(attributes)
      |> Repo.insert!()
    end)
  end
end
