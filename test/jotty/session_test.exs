defmodule Jotty.SessionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Jotty.Assistant
  alias Jotty.Session
  alias Jotty.Session.{RealtimeTranscriptionFailed, TranscriptionPreviewed, UtteranceCompleted}

  test "starts exactly two configured streams and routes source-local PCM" do
    {:ok, session} = start_session()

    streams = started_streams()
    assert Map.keys(streams) |> Enum.sort() == [:microphone, :system]

    Enum.each(streams, fn {_source, %{configuration: configuration}} ->
      assert configuration == %{
               "api_key" => "test-key",
               "audio_format" => "pcm_s16le",
               "enable_endpoint_detection" => true,
               "enable_language_identification" => false,
               "enable_speaker_diarization" => true,
               "model" => "stt-rt-v5",
               "num_channels" => 1,
               "sample_rate" => 16_000
             }
    end)

    Session.live_event(session, {:pcm, :system, <<1, 2>>})
    assert_receive {:transport_binary, system_transport, :system, <<1, 2>>}
    assert system_transport == streams.system.transport
    refute_receive {:transport_binary, _transport, :microphone, <<1, 2>>}

    Session.live_event(session, {:pcm, :microphone, <<3, 4>>})
    assert_receive {:transport_binary, microphone_transport, :microphone, <<3, 4>>}
    assert microphone_transport == streams.microphone.transport
  end

  test "publishes transcription previews to the configured event sink" do
    {:ok, _session} = start_session([], event_sink: self())
    streams = started_streams()

    send(
      streams.system.transport,
      {:text, Jason.encode!(%{"tokens" => [token_map("draft", false, 0, 10, "1")]})}
    )

    assert_receive {:jotty_session_event,
                    %TranscriptionPreviewed{
                      source: :system,
                      chunks: [%{speaker: "1", text: "draft"}]
                    }}
  end

  test "publishes when native recording is ready" do
    {:ok, session} = start_session([], event_sink: self())
    _streams = started_streams()

    Session.live_event(session, :ready)

    assert_receive {:jotty_session_event, :recording_started}
  end

  test "publishes completed utterances to the configured event sink" do
    {:ok, _session} = start_session([], event_sink: self())
    streams = started_streams()

    send(streams.microphone.transport, {:text, token_response("2")})

    send(
      streams.microphone.transport,
      {:text, Jason.encode!(%{"tokens" => [%{"text" => "<end>", "is_final" => true}]})}
    )

    assert_receive {:jotty_session_event,
                    %UtteranceCompleted{
                      source: :microphone,
                      chunks: [%{speaker: "2", text: "done"}]
                    }}
  end

  test "orderly finish sends one empty frame per stream and accepts finished then close" do
    {:ok, session} = start_session()
    streams = started_streams()
    task = Task.async(fn -> Session.finish(session) end)

    assert_receive {:transport_binary, system_transport, :system, <<>>}
    assert_receive {:transport_binary, microphone_transport, :microphone, <<>>}
    assert system_transport == streams.system.transport
    assert microphone_transport == streams.microphone.transport
    refute_receive {:transport_binary, ^system_transport, :system, <<>>}
    refute_receive {:transport_binary, ^microphone_transport, :microphone, <<>>}

    send(streams.system.transport, {:text, token_response("system")})
    send(streams.system.transport, {:text, ~s({"finished":true})})
    send(streams.system.transport, :closed)
    send(streams.microphone.transport, {:text, token_response("microphone")})
    send(streams.microphone.transport, {:text, ~s({"finished":true})})
    send(streams.microphone.transport, :closed)

    assert :ok = Task.await(task)
  end

  @tag :tmp_dir
  test "delivers completed utterances to the assistant and waits for its artifact", %{
    tmp_dir: directory
  } do
    recording_directory = Path.join(directory, "recording")
    context_directory = Path.join(directory, "context")
    bin_directory = Path.join(directory, "bin")

    File.mkdir_p!(recording_directory)
    File.mkdir_p!(context_directory)
    File.mkdir_p!(bin_directory)
    write_assistant_tools(bin_directory)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_directory}:#{original_path}")
    on_exit(fn -> System.put_env("PATH", original_path) end)

    {:ok, assistant} = Assistant.start(recording_directory, [context_directory])
    {:ok, session} = start_session([], assistant: assistant)
    streams = started_streams()

    send(
      streams.system.transport,
      {:text,
       Jason.encode!(%{
         "tokens" => [
           token_map("What does the project use?", true, 0, 100, "1"),
           %{"text" => "<end>", "is_final" => true}
         ]
       })}
    )

    task = Task.async(fn -> Session.finish(session) end)
    assert_receive {:transport_binary, _transport, :system, <<>>}
    assert_receive {:transport_binary, _transport, :microphone, <<>>}

    send(streams.system.transport, {:text, ~s({"finished":true})})
    send(streams.system.transport, :closed)
    send(streams.microphone.transport, {:text, ~s({"finished":true})})
    send(streams.microphone.transport, :closed)

    assert :ok = Task.await(task)
    refute Process.alive?(assistant)

    output = File.read!(Path.join(recording_directory, "assistant.md"))
    assert output =~ "## Find project facts"
    assert output =~ "What does the project use?"
  end

  test "one runtime-owned timeout disables and stops both streams" do
    {:ok, session} = start_session()
    streams = started_streams()
    task = Task.async(fn -> Session.finish(session) end)

    assert_receive {:transport_binary, _transport, :system, <<>>}
    assert_receive {:transport_binary, _transport, :microphone, <<>>}

    log =
      capture_log(fn ->
        send(session, :shutdown_timeout)
        assert {:error, :shutdown_timeout} = Task.await(task)
        assert_receive {:transport_stopped, system_transport, :system}
        assert_receive {:transport_stopped, microphone_transport, :microphone}
        assert system_transport == streams.system.transport
        assert microphone_transport == streams.microphone.transport
        :sys.get_state(session)
        Logger.flush()
      end)

    assert count_disabled(log) == 1
  end

  test "binary send failure disables both streams without reconnect" do
    {:ok, session} = start_session(fail_send_source: :system)
    _streams = started_streams()

    capture_log(fn ->
      Session.live_event(session, {:pcm, :system, <<1>>})
      assert_receive {:transport_binary, _transport, :system, <<1>>}
      assert_receive {:transport_stopped, _transport, :system}
      assert_receive {:transport_stopped, _transport, :microphone}
      refute_receive {:transport_started, _transport, _owner, _source, _configuration}
      :sys.get_state(session)
      Logger.flush()
    end)
  end

  test "provider failure disables both streams once, rejects later PCM, and never reconnects" do
    {:ok, session} = start_session()
    streams = started_streams()

    log =
      capture_log(fn ->
        send(
          streams.system.transport,
          {:text, ~s({"error_code":503,"error_type":"service_unavailable","error_message":"discard me"})}
        )

        assert_receive {:transport_stopped, _transport, :system}
        assert_receive {:transport_stopped, _transport, :microphone}

        send(session, {:DOWN, make_ref(), :process, streams.system.owner, :boom})
        Session.live_event(session, {:pcm, :microphone, <<9>>})
        refute_receive {:transport_binary, _transport, :microphone, <<9>>}
        refute_receive {:transport_started, _transport, _owner, _source, _configuration}
        :sys.get_state(session)
        Logger.flush()
      end)

    assert count_disabled(log) == 1
  end

  test "realtime failure stops assistant processing" do
    {:ok, _session} = start_session([], assistant: self())
    streams = started_streams()

    capture_log(fn ->
      send(
        streams.system.transport,
        {:text, ~s({"error_code":503,"error_type":"service_unavailable"})}
      )

      assert_receive {:"$gen_cast", :disable}
      assert_receive {:transport_stopped, _transport, :system}
      assert_receive {:transport_stopped, _transport, :microphone}
      Logger.flush()
    end)
  end

  test "native transport failure uses the source-less whole-live disable transition" do
    {:ok, session} = start_session()
    _streams = started_streams()

    log =
      capture_log(fn ->
        Session.live_event(session, {:live_transport_failed, :empty_payload})
        assert_receive {:transport_stopped, _transport, :system}
        assert_receive {:transport_stopped, _transport, :microphone}
        assert %{mode: :disabled} = :sys.get_state(session)
        Logger.flush()
      end)

    assert count_disabled(log) == 1
  end

  test "native source failure uses the same whole-live disable transition" do
    {:ok, session} = start_session()
    _streams = started_streams()

    log =
      capture_log(fn ->
        Session.live_event(session, {:live_source_failed, :microphone, :conversion})
        assert_receive {:transport_stopped, _transport, :system}
        assert_receive {:transport_stopped, _transport, :microphone}
        :sys.get_state(session)
        Logger.flush()
      end)

    assert count_disabled(log) == 1
  end

  @tag :tmp_dir
  test "records until its owner sends stop", %{tmp_dir: directory} do
    executable = Path.join(directory, "recorder")
    write_failing_recorder(executable)
    {:ok, session} = start_session(auto_transcribe: true)
    _streams = started_streams()

    task = Task.async(fn -> Session.record(executable, directory, session, stop: :message) end)
    send(task.pid, :stop)

    assert :ok = Task.await(task)
    refute Process.alive?(session)
  end

  test "finished before connection finalization disables realtime" do
    {:ok, session} = start_session()
    streams = started_streams()

    capture_log(fn ->
      send(streams.system.transport, {:text, ~s({"finished":true})})
      assert_receive {:transport_stopped, _transport, :system}
      assert_receive {:transport_stopped, _transport, :microphone}
      :sys.get_state(session)
      Logger.flush()
    end)
  end

  test "unexpected provider frame and premature close are failures" do
    Enum.each([{:binary, <<1>>}, :closed], fn frame ->
      {:ok, session} = start_session()
      streams = started_streams()

      log =
        capture_log(fn ->
          send(streams.system.transport, {:inject, frame})
          assert_receive {:transport_stopped, _transport, :system}
          assert_receive {:transport_stopped, _transport, :microphone}
          :sys.get_state(session)
          Logger.flush()
        end)

      assert count_disabled(log) == 1
    end)
  end

  @tag :tmp_dir
  test "native live failure disables realtime while archival recording completes", %{
    tmp_dir: directory
  } do
    executable = Path.join(directory, "recorder")
    write_failing_recorder(executable)
    {:ok, session} = start_session()
    _streams = started_streams()

    capture_log(fn ->
      capture_io("\n", fn ->
        assert :ok = Session.record(executable, directory, session)
      end)

      Logger.flush()
    end)

    refute Process.alive?(session)
    assert File.exists?(Path.join(directory, "system.m4a"))
    assert File.exists?(Path.join(directory, "microphone.m4a"))
  end

  test "disables realtime before the next external mailbox message" do
    {:ok, session} = start_session([], event_sink: self())
    _streams = started_streams()

    log =
      capture_log(fn ->
        failure = %RealtimeTranscriptionFailed{source: :system, reason: :premature_close}
        send(session, {:stream_event, failure})
        Session.live_event(session, {:pcm, :microphone, <<7>>})

        assert_receive {:jotty_session_event, ^failure}
        assert %{mode: :disabled} = :sys.get_state(session)
        refute_receive {:transport_binary, _transport, :microphone, <<7>>}
        Logger.flush()
      end)

    assert count_disabled(log) == 1
  end

  defp start_session(transport_options \\ [], session_options \\ []) do
    options = [test_pid: self()] ++ transport_options

    session_options =
      [
        api_key: "test-key",
        transport: Jotty.FakeSonioxTransport,
        transport_options: options,
        shutdown_timeout: 60_000
      ] ++ session_options

    Session.start_link(session_options)
  end

  defp started_streams do
    Enum.reduce(1..2, %{}, fn _, streams ->
      assert_receive {:transport_started, transport, owner, source, configuration}

      Map.put(streams, source, %{transport: transport, owner: owner, configuration: configuration})
    end)
  end

  defp token_response(speaker) do
    Jason.encode!(%{"tokens" => [token_map("done", true, 0, 10, speaker)]})
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

  defp write_failing_recorder(executable) do
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

    for payload in [bytes([1]), bytes([4, 2, 1])]:
        sys.stdout.buffer.write(struct.pack(">I", len(payload)) + payload)
        sys.stdout.buffer.flush()

    time.sleep(1)
    raise SystemExit(2)
    """)

    File.chmod!(executable, 0o755)
  end

  defp write_assistant_tools(bin_directory) do
    codex = Path.join(bin_directory, "codex")
    hermes = Path.join(bin_directory, "hermes")

    File.write!(codex, """
    #!/bin/sh
    output=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output-last-message" ]; then
        shift
        output="$1"
      fi
      shift
    done
    printf '%s' '{"decision":{"action":"search","query":"Find project facts"}}' > "$output"
    """)

    File.write!(hermes, """
    #!/bin/sh
    printf 'Project facts.\n'
    """)

    File.chmod!(codex, 0o755)
    File.chmod!(hermes, 0o755)
  end

  defp count_disabled(log) do
    log
    |> String.split("live_assistant_disabled")
    |> Enum.count()
    |> Kernel.-(1)
  end
end
