defmodule Jotty.Recorder do
  @moduledoc """
  Runs the native ScreenCaptureKit recorder and stops it when the user presses Enter.
  """

  @doc """
  Runs the native recorder and waits for its finalized exit status.
  """
  @spec record(Path.t(), Path.t()) ::
          :ok
          | {:error, {:recorder, non_neg_integer()}}
          | {:error, {:recorder_signal, non_neg_integer(), String.t()}}
  def record(executable, directory) do
    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          :use_stdio,
          args: [String.to_charlist(directory)]
        ]
      )

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    await_ready(port, os_pid)
  end

  defp await_ready(port, os_pid) do
    receive do
      {^port, {:data, data}} ->
        IO.binwrite(:stderr, data)
        await_stop(port, os_pid, input_reader())

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

    {pid, reference}
  end

  defp await_stop(port, os_pid, {input_pid, input_reference} = input_reader) do
    receive do
      {^port, {:data, data}} ->
        IO.binwrite(:stderr, data)
        await_stop(port, os_pid, input_reader)

      {^input_reference, :stop} ->
        stop(port, os_pid)

      {^port, {:exit_status, status}} ->
        Process.exit(input_pid, :kill)
        exit_result(status)
    end
  end

  defp stop(port, os_pid) do
    case System.cmd("/bin/kill", ["-INT", Integer.to_string(os_pid)], stderr_to_stdout: true) do
      {_output, 0} -> await_exit(port)
      {output, status} -> {:error, {:recorder_signal, status, String.trim(output)}}
    end
  end

  defp await_exit(port) do
    receive do
      {^port, {:data, data}} ->
        IO.binwrite(:stderr, data)
        await_exit(port)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        exit_result(status)
    end
  end

  defp exit_result(0), do: :ok
  defp exit_result(status), do: {:error, {:recorder, status}}
end
