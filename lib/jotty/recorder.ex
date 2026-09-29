defmodule Jotty.Recorder do
  @moduledoc """
  Runs the native ScreenCaptureKit recorder and stops it when the user presses Enter.
  """

  alias Jotty.LiveAudioPacket

  @type live_event ::
          LiveAudioPacket.frame() | {:live_transport_failed, LiveAudioPacket.protocol_error()}
  @type result ::
          :ok
          | {:error, {:recorder, non_neg_integer()}}
          | {:error, {:recorder_signal, non_neg_integer(), String.t()}}

  @doc """
  Runs the native recorder in archival-only mode and waits for its finalized exit status.
  """
  @spec record(Path.t(), Path.t()) :: result()
  def record(executable, directory) do
    run(executable, directory, [], nil, :stdio)
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
    run(executable, directory, ["--live"], consumer, Keyword.get(options, :stop, :stdio))
  end

  defp run(executable, directory, arguments, consumer, stop_mode) do
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
    await_ready(port, os_pid, consumer, true, stop_mode)
  end

  defp await_ready(port, os_pid, consumer, transport_usable?, stop_mode) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)
        await_stop(port, os_pid, stop_signal(stop_mode), consumer, transport_usable?)

      {^port, {:exit_status, status}} ->
        exit_result(status)
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
         transport_usable?
       ) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)
        await_stop(port, os_pid, stop_signal, consumer, transport_usable?)

      {^input_reference, :stop} ->
        stop(port, os_pid, consumer, transport_usable?)

      {^port, {:exit_status, status}} ->
        Process.exit(input_pid, :kill)
        exit_result(status)
    end
  end

  defp await_stop(port, os_pid, :message, consumer, transport_usable?) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)
        await_stop(port, os_pid, :message, consumer, transport_usable?)

      :stop ->
        stop(port, os_pid, consumer, transport_usable?)

      {^port, {:exit_status, status}} ->
        exit_result(status)
    end
  end

  defp stop(port, os_pid, consumer, transport_usable?) do
    case System.cmd("/bin/kill", ["-INT", Integer.to_string(os_pid)], stderr_to_stdout: true) do
      {_output, 0} -> await_exit(port, consumer, transport_usable?)
      {output, status} -> {:error, {:recorder_signal, status, String.trim(output)}}
    end
  end

  defp await_exit(port, consumer, transport_usable?) do
    receive do
      {^port, {:data, payload}} ->
        transport_usable? = consume(payload, consumer, transport_usable?)
        await_exit(port, consumer, transport_usable?)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        exit_result(status)
    end
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
