defmodule Jotty.STT.Soniox.Transport do
  @moduledoc false

  @callback start(pid(), :mixed, binary(), keyword()) ::
              {:ok, pid()} | {:error, term()}
  @callback send_binary(pid(), binary()) :: :ok | {:error, term()}
  @callback finish(pid()) :: :ok | {:error, term()}
  @callback stop(pid()) :: :ok
end
