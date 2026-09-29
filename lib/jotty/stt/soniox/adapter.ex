defmodule Jotty.STT.Soniox.Adapter do
  @moduledoc false

  alias Jotty.STT.Soniox.Token

  @type item :: Token.t() | :endpoint
  @type response :: {:batch, [item()]} | :finished
  @type error_reason :: {:provider_error, term(), term()}

  @spec decode(binary()) :: response() | {:error, error_reason()}
  def decode(payload) do
    payload
    |> Jason.decode!()
    |> decode_response()
  end

  defp decode_response(%{"tokens" => tokens}) do
    {:batch, Enum.map(tokens, &Token.new/1)}
  end

  defp decode_response(%{"error_code" => code, "error_type" => type}) do
    {:error, {:provider_error, code, type}}
  end

  defp decode_response(%{"finished" => true}), do: :finished
end
