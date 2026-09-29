defmodule Jotty.FakeSonioxTransport do
  @moduledoc false

  @behaviour Jotty.STT.Soniox.Transport

  def start(owner, source, configuration, options) do
    test_pid = Keyword.fetch!(options, :test_pid)
    fail_send? = Keyword.get(options, :fail_send_source) == source
    auto_transcribe? = Keyword.get(options, :auto_transcribe, false)
    pid = spawn(fn -> loop(test_pid, owner, source, fail_send?, auto_transcribe?) end)
    send(test_pid, {:transport_started, pid, owner, source, Jason.decode!(configuration)})
    {:ok, pid}
  end

  def send_binary(pid, binary) do
    reference = make_ref()
    send(pid, {:binary, self(), reference, binary})

    receive do
      {^reference, result} -> result
    end
  end

  def stop(pid) do
    send(pid, :stop)
    :ok
  end

  defp loop(test_pid, owner, source, fail_send?, auto_transcribe?) do
    receive do
      {:binary, sender, reference, binary} ->
        send(test_pid, {:transport_binary, self(), source, binary})
        result = if fail_send?, do: {:error, :send_failed}, else: :ok
        send(sender, {reference, result})
        auto_response(owner, source, binary, result, auto_transcribe?)
        loop(test_pid, owner, source, fail_send?, auto_transcribe?)

      :stop ->
        send(test_pid, {:transport_stopped, self(), source})

      {:text, payload} ->
        send(owner, {:soniox_transport, source, {:text, payload}})
        loop(test_pid, owner, source, fail_send?, auto_transcribe?)

      {:inject, frame} ->
        send(owner, {:soniox_transport, source, frame})
        loop(test_pid, owner, source, fail_send?, auto_transcribe?)

      frame ->
        send(owner, {:soniox_transport, source, frame})
        loop(test_pid, owner, source, fail_send?, auto_transcribe?)
    end
  end

  defp auto_response(owner, source, binary, :ok, true) when binary != <<>> do
    payload =
      Jason.encode!(%{
        "tokens" => [
          %{
            "text" => "What does the project use?",
            "is_final" => true,
            "start_ms" => 0,
            "end_ms" => 100,
            "speaker" => "1"
          },
          %{"text" => "<end>", "is_final" => true}
        ]
      })

    send(owner, {:soniox_transport, source, {:text, payload}})
  end

  defp auto_response(owner, source, <<>>, :ok, true) do
    send(owner, {:soniox_transport, source, {:text, ~s({"finished":true})}})
    send(owner, {:soniox_transport, source, :closed})
  end

  defp auto_response(_owner, _source, _binary, _result, _auto_transcribe?), do: :ok
end
