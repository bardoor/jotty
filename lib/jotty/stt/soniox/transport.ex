defmodule Jotty.STT.Soniox.Transport do
  @moduledoc false

  alias Jotty.LiveAudioPacket

  @callback start(pid(), LiveAudioPacket.source(), binary(), keyword()) ::
              {:ok, pid()} | {:error, term()}
  @callback send_binary(pid(), binary()) :: :ok | {:error, term()}
  @callback stop(pid()) :: :ok
end
