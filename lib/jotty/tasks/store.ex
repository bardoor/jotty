defmodule Jotty.Tasks.Store do
  @moduledoc false

  alias Jotty.Tasks.Card

  @spec read(Path.t()) :: {:ok, [Card.t()]} | {:error, term()}
  def read(path) do
    if File.regular?(path) do
      with {:ok, contents} <- File.read(path),
           {:ok, payloads} when is_list(payloads) <- Jason.decode(contents) do
        {:ok, Enum.map(payloads, &Card.from_map/1)}
      end
    else
      {:ok, []}
    end
  end

  @spec write(Path.t(), [Card.t()]) :: :ok | {:error, term()}
  def write(path, cards) do
    temporary = path <> ".tmp"
    payload = Jason.encode!(Enum.map(cards, &Card.to_map/1))

    with :ok <- File.write(temporary, payload),
         :ok <- File.rename(temporary, path) do
      :ok
    end
  end
end
