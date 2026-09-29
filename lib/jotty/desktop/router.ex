defmodule Jotty.Desktop.Router do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Jotty.Desktop.Socket

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(%{method: "GET", path_info: ["health"]} = conn, _options) do
    send_resp(conn, 200, "ok")
  end

  def call(%{method: "GET", path_info: ["ws"]} = conn, options) do
    controller = Keyword.fetch!(options, :controller)
    WebSockAdapter.upgrade(conn, Socket, controller, timeout: 60_000)
  end

  def call(conn, _options), do: send_resp(conn, 404, "not found")
end
