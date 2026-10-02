defmodule Jotty.TemporaryDirectory do
  @moduledoc false

  @spec create!(String.t()) :: Path.t()
  def create!(prefix) do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{suffix}")

    case File.mkdir(path) do
      :ok -> path
      {:error, :eexist} -> create!(prefix)
      {:error, reason} -> raise File.Error, reason: reason, action: "make directory", path: path
    end
  end
end
