defmodule Jotty.Desktop.Protocol do
  @moduledoc false

  alias Jotty.Session.{TranscriptionPreviewed, UtteranceCompleted}

  @spec decode!(String.t()) :: :start | :stop
  def decode!(payload) do
    payload
    |> Jason.decode!()
    |> command()
  end

  @spec encode_event(TranscriptionPreviewed.t() | UtteranceCompleted.t() | map()) :: String.t()
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

  def encode_event(%{type: :snapshot} = snapshot) do
    snapshot
    |> Map.update!(
      :utterances,
      &Enum.map(&1, fn event -> transcription_payload(event, "utterance_completed") end)
    )
    |> Map.update!(:previews, &Map.new(&1, fn {source, event} -> {source, preview_payload(event)} end))
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
      source: event.source,
      chunks: Enum.map(event.chunks, &Map.from_struct/1)
    }
  end

  defp preview_payload(nil), do: nil
  defp preview_payload(event), do: transcription_payload(event, "transcription_previewed")
end
