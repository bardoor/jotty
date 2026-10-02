defmodule Jotty.Recorder do
  @moduledoc """
  Runs the native ScreenCaptureKit recorder and stops it when the user presses Enter.
  """

  alias Jotty.LiveAudioPacket

  @startup_timeout 30_000
  @stop_timeout 15_000
  @termination_timeout 1_000

  @type live_event ::
          LiveAudioPacket.frame() | {:live_transport_failed, LiveAudioPacket.protocol_error()}
  @type result ::
          :ok
          | {:error, {:recorder, non_neg_integer()}}
          | {:error, {:recorder_signal, non_neg_integer(), String.t()}}
          | {:error, :recorder_start_timeout | :recorder_stop_timeout}

  @doc """
  Runs the native recorder in archival-only mode and waits for its finalized exit status.
  """
  @spec record(Path.t(), Path.t()) :: result()
  def record(executable, directory) do
    run(executable, directory, [], nil, stop: :stdio)
  end

  @doc """
  Runs the native recorder with live PCM enabled and delivers decoded live events to `consumer`.
  """
  @spec record_live(Path.t(), Path.t(), (live_event() -> any())) :: result()
  def record_live(executable, directory, consumer) do
    record_live(executable, directory, consumer, [])
  end

  @spec record_live(Path.t(), Path.t(), (live_event() -> any()), keyword()) :: result()
  def record_live(executable, directory, consumer, options) do
    run(executable, directory, ["--live"], consumer, options)
  end

  defp run(executable, directory, arguments, consumer, options) do
    args = Enum.map(arguments ++ [directory], &String.to_charlist/1)

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [
          :binary,
          :exit_status,
          :use_stdio,
          {:packet, 4},
          args: args
        ]
      )

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    startup_timeout = Keyword.get(options, :startup_timeout, @startup_timeout)
    termination_timeout = Keyword.get(options, :termination_timeout, @termination_timeout)
    stop_options = {Keyword.get(options, :stop, :stdio), Keyword.get(options, :stop_timeout, @stop_timeout)}

    await_ready(port, os_pid, consumer, true, stop_options, startup_timeout, termination_timeout)
  end

  defp await_ready(
         port,
         os_pid,
         consumer,
         transport_usable?,
         {stop_mode, stop_timeout},
         startup_timeout,
         termination_timeout
       ) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)

        await_stop(
          port,
          os_pid,
          stop_signal(stop_mode),
          consumer,
          transport_usable?,
          stop_timeout,
          termination_timeout
        )

      {^port, {:exit_status, status}} ->
        exit_result(status)
    after
      startup_timeout ->
        terminate_recorder(port, os_pid, :recorder_start_timeout, termination_timeout)
    end
  end

  defp input_reader do
    receiver = self()
    reference = make_ref()

    pid =
      spawn(fn ->
        IO.gets("Press Enter to stop recording.\n")
        send(receiver, {reference, :stop})
      end)

    {:stdio, pid, reference}
  end

  defp stop_signal(:stdio), do: input_reader()
  defp stop_signal(:message), do: :message

  defp await_stop(
         port,
         os_pid,
         {:stdio, input_pid, input_reference} = stop_signal,
         consumer,
         transport_usable?,
         stop_timeout,
         termination_timeout
       ) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)

        await_stop(
          port,
          os_pid,
          stop_signal,
          consumer,
          transport_usable?,
          stop_timeout,
          termination_timeout
        )

      {^input_reference, :stop} ->
        stop(port, os_pid, consumer, transport_usable?, stop_timeout, termination_timeout)

      {^port, {:exit_status, status}} ->
        Process.exit(input_pid, :kill)
        exit_result(status)
    end
  end

  defp await_stop(
         port,
         os_pid,
         :message,
         consumer,
         transport_usable?,
         stop_timeout,
         termination_timeout
       ) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)

        await_stop(
          port,
          os_pid,
          :message,
          consumer,
          transport_usable?,
          stop_timeout,
          termination_timeout
        )

      :stop ->
        stop(port, os_pid, consumer, transport_usable?, stop_timeout, termination_timeout)

      {^port, {:exit_status, status}} ->
        exit_result(status)
    end
  end

  defp stop(port, os_pid, consumer, transport_usable?, stop_timeout, termination_timeout) do
    case System.cmd("/bin/kill", ["-INT", Integer.to_string(os_pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        await_exit(
          port,
          os_pid,
          consumer,
          transport_usable?,
          deadline(stop_timeout),
          termination_timeout
        )

      {output, status} ->
        {:error, {:recorder_signal, status, String.trim(output)}}
    end
  end

  defp await_exit(port, os_pid, consumer, transport_usable?, stop_deadline, termination_timeout) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)
        await_exit(port, os_pid, consumer, transport_usable?, stop_deadline, termination_timeout)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        exit_result(status)
    after
      remaining(stop_deadline) ->
        terminate_recorder(port, os_pid, :recorder_stop_timeout, termination_timeout)
    end
  end

  defp terminate_recorder(port, os_pid, reason, timeout) do
    signal(os_pid, "-TERM")
    await_termination(port, os_pid, deadline(timeout), timeout)
    {:error, reason}
  end

  defp await_termination(port, os_pid, termination_deadline, timeout) do
    receive do
      {^port, {:exit_status, _status}} -> :ok
      {^port, {:data, _payload}} -> await_termination(port, os_pid, termination_deadline, timeout)
    after
      remaining(termination_deadline) ->
        signal(os_pid, "-KILL")
        await_killed(port, deadline(timeout))
    end
  end

  defp await_killed(port, kill_deadline) do
    receive do
      {^port, {:exit_status, _status}} -> :ok
      {^port, {:data, _payload}} -> await_killed(port, kill_deadline)
    after
      remaining(kill_deadline) ->
        if Port.info(port) != nil, do: Port.close(port)
    end
  end

  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp signal(os_pid, signal) do
    System.cmd("/bin/kill", [signal, Integer.to_string(os_pid)], stderr_to_stdout: true)
    :ok
  end

  defp consume(_payload, _consumer, false), do: false

  defp consume(_payload, nil, transport_usable?), do: transport_usable?

  defp consume(payload, consumer, true) do
    case LiveAudioPacket.decode(payload) do
      {:ok, frame} ->
        consumer.(frame)
        true

      {:error, reason} ->
        consumer.({:live_transport_failed, reason})
        false
    end
  end

  defp exit_result(0), do: :ok
  defp exit_result(status), do: {:error, {:recorder, status}}
end
