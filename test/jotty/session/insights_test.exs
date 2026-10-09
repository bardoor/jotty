defmodule Jotty.Session.InsightsTest do
  use ExUnit.Case, async: true

  alias Jotty.Recording
  alias Jotty.Session.Events
  alias Jotty.Session.Events.SessionFailed
  alias Jotty.Session.State

  @tag :tmp_dir
  test "stops a partially started insight worker when session startup fails", %{tmp_dir: directory} do
    insights = spawn(fn -> receive do: ({:"$gen_cast", :disable} -> :ok) end)
    reference = Process.monitor(insights)
    state = State.new(api_key: "unused", recorder: "/unused", recording: recording(directory))
    state = %{state | insights: %{state.insights | pid: insights}}

    state = Events.dispatch(state, %SessionFailed{reason: :stream_start_failed})

    assert state.insights.pid == nil
    assert_receive {:DOWN, ^reference, :process, ^insights, :normal}
  end

  defp recording(directory) do
    %Recording{
      directory: directory,
      system_audio: Path.join(directory, "system.m4a"),
      microphone_audio: Path.join(directory, "microphone.m4a"),
      transcript: Path.join(directory, "transcript.txt"),
      summary: Path.join(directory, "summary.md")
    }
  end
end
