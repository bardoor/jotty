defmodule Jotty.Desktop.Router do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Jotty.Desktop.Socket
  alias Jotty.Sessions.Catalog

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(%{method: "GET", path_info: ["health"]} = conn, _options), do: send_resp(conn, 200, "ok")

  def call(%{method: "GET", path_info: ["ws"]} = conn, options) do
    socket_context = Keyword.fetch!(options, :socket_context)
    WebSockAdapter.upgrade(conn, Socket, socket_context, timeout: :infinity)
  end

  def call(%{method: "GET", path_info: ["sessions", id, "audio"]} = conn, _options) do
    case Catalog.playback_path(id) do
      {:ok, path} -> send_audio(conn, path)
      {:error, _reason} -> send_resp(conn, 404, "not found")
    end
  end

  def call(conn, _options), do: send_resp(conn, 404, "not found")

  defp send_audio(conn, path) do
    size = File.stat!(path).size

    conn =
      conn
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("content-type", "audio/mp4")

    case get_req_header(conn, "range") do
      [] ->
        conn
        |> put_resp_header("content-length", Integer.to_string(size))
        |> send_file(200, path)

      [range] ->
        send_range(conn, path, size, range)

      _ranges ->
        range_not_satisfiable(conn, size)
    end
  end

  defp send_range(conn, path, size, range) do
    case parse_range(range, size) do
      {:ok, first, last} ->
        length = last - first + 1

        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> put_resp_header("content-length", Integer.to_string(length))
        |> send_file(206, path, first, length)

      :error ->
        range_not_satisfiable(conn, size)
    end
  end

  defp range_not_satisfiable(conn, size) do
    conn
    |> put_resp_header("content-range", "bytes */#{size}")
    |> send_resp(416, "range not satisfiable")
  end

  defp parse_range("bytes=" <> range, size) when size > 0 do
    case String.split(range, "-", parts: 2) do
      ["", suffix] -> parse_suffix(suffix, size)
      [first, ""] -> parse_open_range(first, size)
      [first, last] -> parse_closed_range(first, last, size)
      _parts -> :error
    end
  end

  defp parse_range(_range, _size), do: :error

  defp parse_suffix(value, size) do
    with {:ok, suffix} when suffix > 0 <- parse_byte_position(value) do
      first = max(size - suffix, 0)
      {:ok, first, size - 1}
    else
      _reason -> :error
    end
  end

  defp parse_open_range(value, size) do
    with {:ok, first} when first < size <- parse_byte_position(value) do
      {:ok, first, size - 1}
    else
      _reason -> :error
    end
  end

  defp parse_closed_range(first_value, last_value, size) do
    with {:ok, first} <- parse_byte_position(first_value),
         {:ok, last} when last >= first <- parse_byte_position(last_value),
         true <- first < size do
      {:ok, first, min(last, size - 1)}
    else
      _reason -> :error
    end
  end

  defp parse_byte_position(value) do
    if Regex.match?(~r/\A[0-9]+\z/, value), do: {:ok, String.to_integer(value)}, else: :error
  end
end
