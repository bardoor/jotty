defmodule Jotty.LogFormatter do
  @moduledoc false

  @spec format(:logger.log_event(), map()) :: IO.chardata()
  def format(%{level: level, msg: message, meta: metadata}, _config) do
    metadata_fields =
      ~w(scope session_id recording_id provider model sample_rate num_channels audio_format reason source result stage context_count utterance_count timeout_ms)a

    timestamp =
      metadata.time
      |> DateTime.from_unix!(:microsecond)
      |> DateTime.to_iso8601()

    payload = %{
      timestamp: timestamp,
      level: level,
      event: format_message(message)
    }

    encoded =
      metadata
      |> Map.filter(fn {key, _value} -> key in metadata_fields end)
      |> Map.merge(payload)
      |> Jason.encode_to_iodata!()

    [encoded, "\n"]
  end

  defp format_message({:string, message}), do: IO.chardata_to_string(message)
  defp format_message({:report, report}), do: inspect(report)

  defp format_message({format, arguments}) do
    format
    |> :io_lib.format(arguments)
    |> IO.chardata_to_string()
  end

  defp format_message(message), do: inspect(message)
end
