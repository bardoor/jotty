defmodule Jotty.SessionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jotty.Recording

  alias Jotty.Session.Events.{
    AudioReceived,
    RealtimeTranscriptionFailed,
    RecorderFinished,
    RecordingStarted,
    SessionCompleted,
    SessionFailed,
    SessionStarting,
    TranscriptReady,
    TranscriptionPreviewed,
    UtteranceCompleted
  }

  alias Jotty.Session.{Events, Server, State}

  defmodule FakeSummarizer do
    def summarize(_transcript, summary) do
      File.write(summary, "# Summary\nDone.\n")
    end
  end

  defmodule BlockingSummarizer do
    def summarize(_transcript, summary) do
      test = Process.whereis(:jotty_blocking_summarizer_test)
      send(test, {:summary_started, self()})

      receive do
        :continue -> File.write(summary, "# Summary\nDone.\n")
      end
    end
  end

  defmodule FailingTransport do
    def start(_owner, _source, _configuration, _options), do: {:error, :unavailable}
  end

  @tag :tmp_dir
  test "routes start, native readiness, and PCM through typed messages", %{tmp_dir: directory} do
    {session, stream} = start_recording(directory)

    Server.publish(session, %AudioReceived{pcm: <<1, 2>>})

    assert_receive {:transport_binary, transport, :mixed, <<1, 2>>}
    assert transport == stream.transport
    refute_receive {:transport_started, _transport, _owner, _source, _configuration}

    finish_recording(session, stream)
  end

  @tag :tmp_dir
  test "publishes provider previews through the session event sink", %{tmp_dir: directory} do
    {session, stream} = start_recording(directory)

    send(
      stream.transport,
      {:text, Jason.encode!(%{"tokens" => [token_map("draft", false, 0, 10, "1")]})}
    )

    assert_receive {:jotty_session_event, %TranscriptionPreviewed{chunks: [%{speaker: "1", text: "draft"}]}}

    finish_recording(session, stream)
  end

  @tag :tmp_dir
  test "persists endpoint-completed utterances and summarizes after stop", %{tmp_dir: directory} do
    {session, stream, recording} = start_recording(directory, return_recording: true)

    send(stream.transport, {:text, completed_response("done", "2")})

    assert_receive {:jotty_session_event, %UtteranceCompleted{chunks: [%{speaker: "2", text: "done"}]}}
    assert {:ok, ^recording} = finish_recording(session, stream)
    assert File.read!(recording.transcript) == "Speaker 2: done"
    assert File.read!(recording.summary) == "# Summary\nDone.\n"
  end

  @tag :tmp_dir
  test "applies a realtime failure before the next queued PCM message", %{tmp_dir: directory} do
    {session, _stream} = start_recording(directory)
    failure = %RealtimeTranscriptionFailed{source: nil, reason: :premature_close}

    Server.publish(session, failure)
    Server.publish(session, %AudioReceived{pcm: <<7>>})

    assert_receive {:jotty_session_event, ^failure}
    assert_receive {:transport_stopped, transport, :mixed}
    refute_receive {:transport_binary, ^transport, :mixed, <<7>>}

    :ok = Server.stop_recording(session)

    assert_receive {:jotty_session_event,
                    %SessionFailed{reason: {:realtime_transcription_failed, :premature_close}}},
                   2_000

    GenServer.stop(session)
  end

  @tag :tmp_dir
  test "runs summary work outside the session mailbox", %{tmp_dir: directory} do
    Process.register(self(), :jotty_blocking_summarizer_test)

    recording = recording(directory)
    File.write!(recording.transcript, "Speaker 1: done")

    {:ok, session} =
      Server.start_link(
        api_key: "test-key",
        recorder: fake_live_recorder!(directory),
        recording: recording,
        summarizer: BlockingSummarizer,
        event_sinks: [self()]
      )

    Server.publish(session, %RecorderFinished{result: :ok})
    Server.publish(session, %TranscriptReady{path: recording.transcript})

    assert_receive {:summary_started, summary_worker}

    snapshot_task = Task.async(fn -> Server.attach(session, self()) end)
    assert %{status: :idle} = Task.await(snapshot_task, 500)

    send(summary_worker, :continue)
    assert_receive {:jotty_session_event, %SessionCompleted{result: {:ok, ^recording}}}
    GenServer.stop(session)
  end

  @tag :tmp_dir
  test "stops resources acquired before a later startup failure", %{tmp_dir: directory} do
    recording = recording(directory)

    {:ok, session} =
      Server.start_link(
        api_key: "test-key",
        event_sinks: [self()],
        recorder: fake_live_recorder!(directory),
        recorder_options: [stop: :message],
        recording: recording,
        transport: FailingTransport
      )

    :ok = Server.start_recording(session)

    assert_receive {:jotty_session_event, %SessionFailed{reason: {:stream_start, _reason}}}, 2_000
    refute_receive {:jotty_session_event, %RecordingStarted{}}
    assert_eventually(fn -> File.exists?(recording.system_audio) end)
    GenServer.stop(session)
  end

  @tag :tmp_dir
  test "logs a correlated startup failure and recorder shutdown", %{tmp_dir: directory} do
    recording = recording(directory)

    log =
      capture_log([metadata: [:scope, :session_id, :recording_id, :provider, :reason]], fn ->
        {:ok, session} =
          Server.start_link(
            api_key: "test-key",
            event_sinks: [self()],
            recorder: fake_live_recorder!(directory),
            recorder_options: [stop: :message],
            recording: recording,
            transport: FailingTransport
          )

        :ok = Server.start_recording(session)
        assert_receive {:jotty_session_event, %SessionFailed{}}, 2_000
        assert_eventually(fn -> File.exists?(recording.system_audio) end)
        GenServer.stop(session)
        Logger.flush()
      end)

    assert log =~ "starting"
    assert log =~ "scope=session"
    assert log =~ "scope=recording"
    assert log =~ "scope=transcription"
    assert log =~ "failed"
    assert log =~ "reason={:stream_start, {:transport_start, :unavailable}}"
    assert log =~ "recording_id=#{Path.basename(directory)}"
  end

  @tag :tmp_dir
  test "logs the successful recording, transcription, transcript, and summary lifecycle", %{tmp_dir: directory} do
    log =
      capture_log([metadata: [:scope, :session_id, :recording_id, :provider, :result, :reason]], fn ->
        {session, stream} = start_recording(directory)
        send(stream.transport, {:text, completed_response("done", "1")})
        assert {:ok, _recording} = finish_recording(session, stream)
        Logger.flush()
      end)

    assert log =~ "scope=session"
    assert log =~ "recording"
    assert log =~ "completed"
    assert log =~ "scope=recording"
    assert log =~ "ready"
    assert log =~ "reason=:requested"
    assert log =~ "finished"
    assert log =~ "scope=transcription"
    assert log =~ "started"
    assert log =~ "finishing"
    assert log =~ "finish_frame_sent"
    assert log =~ "terminal_response_received"
    assert log =~ "stream_terminated"
    assert log =~ "scope=transcript"
    assert log =~ "scope=summary"
    refute log =~ "reason=:session_terminating"
  end

  @tag :tmp_dir
  test "does not log recorder shutdown after the recorder already finished", %{tmp_dir: directory} do
    state =
      State.new(
        api_key: "test-key",
        recorder: "/unused",
        recording: recording(directory)
      )

    log =
      capture_log([metadata: [:scope, :reason]], fn ->
        Events.dispatch(state, %SessionFailed{reason: :late_failure})
        Logger.flush()
      end)

    refute log =~ "reason=:session_failed"
  end

  defp start_recording(directory, options \\ []) do
    recording = recording(directory)

    {:ok, session} =
      Server.start_link(
        api_key: "test-key",
        event_sinks: [self()],
        recorder: fake_live_recorder!(directory),
        recorder_options: [stop: :message],
        recording: recording,
        shutdown_timeout: 1_000,
        summarizer: FakeSummarizer,
        transport: Jotty.FakeSonioxTransport,
        transport_options: [test_pid: self()]
      )

    :ok = Server.start_recording(session)

    assert_receive {:transport_started, transport, owner, :mixed, configuration}
    assert_receive {:jotty_session_event, %SessionStarting{}}
    assert_receive {:jotty_session_event, %RecordingStarted{}}, 2_000

    stream = %{transport: transport, owner: owner, configuration: configuration}

    if Keyword.get(options, :return_recording, false) do
      {session, stream, recording}
    else
      {session, stream}
    end
  end

  defp finish_recording(session, stream) do
    :ok = Server.stop_recording(session)
    assert_receive {:transport_finished, transport, :mixed}, 2_000
    assert transport == stream.transport

    send(stream.transport, {
      :text,
      ~s({"tokens":[],"final_audio_proc_ms":100,"total_audio_proc_ms":100,"finished":true})
    })

    assert_receive {:jotty_session_event, %SessionCompleted{result: result}}, 2_000
    GenServer.stop(session)
    result
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

  defp assert_eventually(assertion, attempts \\ 100)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")

  defp fake_live_recorder!(directory) do
    executable = Path.join(directory, "live-recorder")

    File.write!(executable, """
    #!/usr/bin/python3
    import pathlib
    import signal
    import struct
    import sys
    import time

    output = pathlib.Path(sys.argv[-1])

    def stop(_signal, _frame):
        (output / "system.m4a").touch()
        (output / "microphone.m4a").touch()
        raise SystemExit(0)

    signal.signal(signal.SIGINT, stop)
    payload = bytes([1])
    sys.stdout.buffer.write(struct.pack(">I", len(payload)) + payload)
    sys.stdout.buffer.flush()

    while True:
        time.sleep(1)
    """)

    File.chmod!(executable, 0o755)
    executable
  end

  defp completed_response(text, speaker) do
    Jason.encode!(%{
      "tokens" => [
        token_map(text, true, 0, 100, speaker),
        %{"text" => "<end>", "is_final" => true}
      ]
    })
  end

  defp token_map(text, final?, start_ms, end_ms, speaker) do
    %{
      "text" => text,
      "is_final" => final?,
      "start_ms" => start_ms,
      "end_ms" => end_ms,
      "speaker" => speaker
    }
  end
end
