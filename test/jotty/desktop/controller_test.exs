defmodule Jotty.Desktop.ControllerTest do
  use ExUnit.Case, async: false

  alias Jotty.Desktop.Commands.{OpenSession, StartSession, StopSession}
  alias Jotty.Desktop.Controller
  alias Jotty.Desktop.Events.{CommandRejected, SessionOpened}
  alias Jotty.Recording
  alias Jotty.Repo
  alias Jotty.Sessions.{Recordings, Session, SessionContext, TranscriptChunk}
  alias Jotty.Settings
  alias Jotty.Settings.Context

  setup do
    Repo.delete_all(TranscriptChunk)
    Repo.delete_all(SessionContext)
    Repo.delete_all(Session)
    Repo.delete_all(Context)
    :ok
  end

  @tag :tmp_dir
  test "takes fresh resources at start, allows one active session, and reconnects from its snapshot", %{
    tmp_dir: home
  } do
    context_path = Path.join(home, "project")
    File.mkdir_p!(context_path)
    {:ok, context} = Settings.add_context(context_path)
    recorder = fake_recorder!(home)

    {:ok, controller} =
      Controller.start_link(
        home: home,
        recorder: recorder,
        audio_base_url: "http://127.0.0.1:4765",
        session_options: [
          api_key: "test-key",
          transport: Jotty.FakeSonioxTransport,
          transport_options: [test_pid: self()]
        ]
      )

    assert %{status: :idle} = Controller.attach(controller, self())
    assert :ok = Controller.command(controller, %StartSession{})
    assert_receive {:jotty_desktop_event, %{type: :state, status: :starting}}
    assert_receive {:transport_started, _transport, _owner, :mixed, _configuration}
    assert_receive {:jotty_desktop_event, %{type: :state, status: :recording}}, 2_000

    assert {:event, %CommandRejected{command: :start_session}} =
             Controller.command(controller, %StartSession{})

    assert %{status: :recording} = Controller.attach(controller, self())
    [session] = Repo.all(Session)
    assert session.status == :recording

    assert [%SessionContext{context_id: context_id, name: "project", path: ^context_path}] =
             Repo.all(SessionContext)

    assert context_id == context.id
    assert File.read!(Path.join(home, "enumerations")) == "1"

    assert :ok = Controller.command(controller, %StopSession{})
    assert_receive {:jotty_desktop_event, %{type: :state, status: :stopping}}
    GenServer.stop(controller)
    assert Repo.get!(Session, session.id).status == :failed
  end

  @tag :tmp_dir
  test "restores the controller-owned historical selection after reattachment", %{tmp_dir: home} do
    recording = Recording.create!(home, DateTime.utc_now())
    session = Recordings.create!(recording, DateTime.utc_now(), [])
    {:ok, _session} = Recordings.complete(session.id, [], DateTime.utc_now())

    {:ok, controller} = start_controller(home)

    assert {:event, %SessionOpened{session: %{id: id}}} =
             Controller.command(controller, %OpenSession{id: session.id})

    assert id == session.id
    assert %{status: :idle} = Controller.attach(controller, self())
    assert_receive {:jotty_desktop_event, %SessionOpened{session: %{id: ^id}}}
    GenServer.stop(controller)
  end

  @tag :tmp_dir
  test "a dead active child does not crash attach and is durably failed", %{tmp_dir: home} do
    File.mkdir_p!(Path.join(home, "project"))
    recorder = fake_recorder!(home)
    {:ok, controller} = start_controller(home, recorder)
    assert %{status: :idle} = Controller.attach(controller, self())
    assert :ok = Controller.command(controller, %StartSession{})
    assert_receive {:transport_started, _transport, _owner, :mixed, _configuration}
    assert_receive {:jotty_desktop_event, %{type: :state, status: :recording}}, 2_000

    %{active: %{pid: live_pid, id: id}} = :sys.get_state(controller)
    dead_pid = spawn(fn -> :ok end)
    monitor = Process.monitor(dead_pid)
    assert_receive {:DOWN, ^monitor, :process, ^dead_pid, :normal}

    :sys.replace_state(controller, fn state ->
      active = %{state.active | pid: dead_pid}
      %{state | active: active}
    end)

    assert %{status: :idle} = Controller.attach(controller, self())
    assert_receive {:jotty_desktop_event, %SessionOpened{session: %{id: ^id}}}
    assert Process.alive?(controller)
    assert Repo.get!(Session, id).status == :failed

    GenServer.stop(live_pid)
    GenServer.stop(controller)
  end

  defp start_controller(home, recorder \\ "/usr/bin/true") do
    Controller.start_link(
      home: home,
      recorder: recorder,
      audio_base_url: "http://127.0.0.1:4765",
      session_options: [
        api_key: "test-key",
        transport: Jotty.FakeSonioxTransport,
        transport_options: [test_pid: self()]
      ]
    )
  end

  defp fake_recorder!(home) do
    executable = Path.join(home, "controller-recorder")

    File.write!(executable, """
    #!/usr/bin/python3
    import pathlib
    import signal
    import struct
    import sys
    import time

    home = pathlib.Path(#{inspect(home)})
    if sys.argv[1:] == ["--list-microphones"]:
        count = home / "enumerations"
        count.write_text(str(int(count.read_text()) + 1) if count.exists() else "1")
        print('[{"id":"test-mic","name":"Test Mic"}]')
        raise SystemExit(0)

    output = pathlib.Path(sys.argv[-1])
    def stop(_signal, _frame):
        for name in ["system.m4a", "microphone.m4a", "microphone-aec.wav", "audio.m4a"]:
            (output / name).touch()
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
end
