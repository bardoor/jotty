defmodule Jotty.Desktop.ContextApproval do
  @moduledoc false

  @spec valid?(String.t() | nil, Path.t(), String.t()) :: boolean()
  def valid?(nil, _path, _approval), do: false

  def valid?(secret, path, approval) do
    expected = Base.encode16(:crypto.mac(:hmac, :sha256, secret, path), case: :lower)
    byte_size(expected) == byte_size(approval) and Plug.Crypto.secure_compare(expected, approval)
  end
end
