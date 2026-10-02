defmodule Jotty.LogFormatterTest do
  use ExUnit.Case, async: true

  test "encodes the event and selected metadata as one JSON line" do
    event = %{
      level: :error,
      msg: {:string, "failed"},
      meta: %{
        time: 0,
        scope: :transcription,
        session_id: "<0.123.0>",
        recording_id: "20261002-154356",
        provider: :soniox,
        reason: inspect({:stream_start, :unavailable})
      }
    }

    assert event |> Jotty.LogFormatter.format(%{}) |> IO.iodata_to_binary() |> Jason.decode!() == %{
             "event" => "failed",
             "level" => "error",
             "provider" => "soniox",
             "reason" => "{:stream_start, :unavailable}",
             "recording_id" => "20261002-154356",
             "scope" => "transcription",
             "session_id" => "<0.123.0>",
             "timestamp" => "1970-01-01T00:00:00.000000Z"
           }
  end

  test "configures the default Logger handler to emit JSON" do
    assert {:ok, %{formatter: {Jotty.LogFormatter, %{}}}} = :logger.get_handler_config(:default)
  end

  test "encodes OTP report messages without crashing" do
    event = %{
      level: :notice,
      msg: {:report, %{label: {:error_logger, :info_msg}, format: "SIGTERM received"}},
      meta: %{time: 0}
    }

    decoded = event |> Jotty.LogFormatter.format(%{}) |> IO.iodata_to_binary() |> Jason.decode!()

    assert decoded["event"] =~ "SIGTERM received"
    assert decoded["level"] == "notice"
    assert decoded["timestamp"] == "1970-01-01T00:00:00.000000Z"
  end
end
