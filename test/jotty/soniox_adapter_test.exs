defmodule Jotty.STT.Soniox.AdapterTest do
  use ExUnit.Case, async: true

  alias Jotty.STT.Soniox.{Adapter, Token}

  test "normalizes tokens and lifecycle messages" do
    payload =
      Jason.encode!(%{
        "tokens" => [
          %{
            "text" => "Hello ",
            "is_final" => true,
            "start_ms" => 0,
            "end_ms" => 120,
            "speaker" => "1"
          },
          %{"text" => "<end>", "is_final" => true}
        ]
      })

    assert {:batch,
            [
              %Token{text: "Hello ", final?: true, start_ms: 0, end_ms: 120, speaker: "1"},
              :endpoint
            ]} = Adapter.decode(payload)

    assert :finished =
             Adapter.decode(
               ~s({"tokens":[],"final_audio_proc_ms":1560,"total_audio_proc_ms":1680,"finished":true})
             )

    assert {:error, {:provider_error, 400, "invalid_request"}} =
             Adapter.decode(~s({"error_code":400,"error_type":"invalid_request"}))
  end
end
