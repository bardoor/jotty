defmodule Jotty.Session.AssistantTest do
  use ExUnit.Case, async: true

  alias Jotty.Recording
  alias Jotty.Session.Events
  alias Jotty.Session.Events.SessionFailed
  alias Jotty.Session.State

  @tag :tmp_dir
  test "stops a partially started assistant when session startup fails", %{tmp_dir: directory} do
    assistant = spawn(fn -> receive do: ({:"$gen_cast", :disable} -> :ok) end)
    reference = Process.monitor(assistant)
    state = State.new(api_key: "unused", recorder: "/unused", recording: recording(directory))
    state = %{state | assistant: %{state.assistant | pid: assistant}}

    state = Events.dispatch(state, %SessionFailed{reason: :stream_start_failed})

    assert state.assistant.pid == nil
    assert_receive {:DOWN, ^reference, :process, ^assistant, :normal}
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
