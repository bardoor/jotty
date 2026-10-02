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
    session = Keyword.fetch!(options, :session)
    WebSockAdapter.upgrade(conn, Socket, session, timeout: :infinity)
  end

  def call(conn, _options), do: send_resp(conn, 404, "not found")
end
