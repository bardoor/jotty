defmodule Jotty.Desktop.Protocol do
  @moduledoc false

  alias Jotty.Session.Events.{TranscriptionPreviewed, UtteranceCompleted}
  alias Jotty.Session.Presentation.Snapshot

  @spec decode!(String.t()) :: :start | :stop
  def decode!(payload) do
    payload
    |> Jason.decode!()
    |> command()
  end

  @spec encode_event(TranscriptionPreviewed.t() | UtteranceCompleted.t() | Snapshot.t() | map()) :: String.t()
  def encode_event(%TranscriptionPreviewed{} = event) do
    event
    |> transcription_payload("transcription_previewed")
    |> Jason.encode!()
  end

  def encode_event(%UtteranceCompleted{} = event) do
    event
    |> transcription_payload("utterance_completed")
    |> Jason.encode!()
  end

  def encode_event(%Snapshot{} = snapshot) do
    snapshot
    |> Map.from_struct()
    |> Map.update!(
      :utterances,
      &Enum.map(&1, fn event -> transcription_payload(event, "utterance_completed") end)
    )
    |> Map.update!(:preview, &preview_payload/1)
    |> Jason.encode!()
  end

  def encode_event(%{type: type} = event)
      when type in [:state, :summary_ready, :failed, :realtime_transcription_failed],
      do: Jason.encode!(event)

  defp command(%{"type" => "start"}), do: :start
  defp command(%{"type" => "stop"}), do: :stop

  defp transcription_payload(event, type) do
    %{
      type: type,
      chunks: Enum.map(event.chunks, &Map.from_struct/1)
    }
  end

  defp preview_payload(nil), do: nil
  defp preview_payload(event), do: transcription_payload(event, "transcription_previewed")
end
