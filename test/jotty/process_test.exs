defmodule Jotty.ProcessTest do
  use ExUnit.Case, async: true

  test "spawn_monitor propagates Logger metadata" do
    test = self()
    Logger.metadata(session_id: "<0.123.0>", recording_id: "20261002-154356")

    {pid, reference} =
      Jotty.Process.spawn_monitor(fn ->
        send(test, {:metadata, Logger.metadata()})
      end)

    assert_receive {:metadata, metadata}
    assert metadata[:session_id] == "<0.123.0>"
    assert metadata[:recording_id] == "20261002-154356"
    assert_receive {:DOWN, ^reference, :process, ^pid, :normal}
  end
end
