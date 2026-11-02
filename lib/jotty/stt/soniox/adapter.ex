defmodule Jotty.STT.Soniox.Adapter do
  @moduledoc false

  alias Jotty.STT.Soniox.Token

  @type item :: Token.t() | :endpoint
  @type response :: {:batch | :finished, [item()], non_neg_integer()}
  @type error_reason :: {:provider_error, term(), term()}

  @spec decode(binary()) :: response() | {:error, error_reason()}
  def decode(payload) do
    payload
    |> Jason.decode!()
    |> decode_response()
  end

  defp decode_response(%{"error_code" => code, "error_type" => type}) do
    {:error, {:provider_error, code, type}}
  end

  defp decode_response(%{"finished" => true, "tokens" => tokens, "final_audio_proc_ms" => final_audio_proc_ms}) do
    {:finished, Enum.map(tokens, &Token.new/1), final_audio_proc_ms}
  end

  defp decode_response(%{"tokens" => tokens, "final_audio_proc_ms" => final_audio_proc_ms}) do
    {:batch, Enum.map(tokens, &Token.new/1), final_audio_proc_ms}
  end
end
