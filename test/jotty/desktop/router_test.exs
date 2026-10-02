defmodule Jotty.Desktop.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Jotty.Desktop.Router

  test "serves a loopback health endpoint" do
    conn = Router.call(conn(:get, "/health"), Router.init(session: self()))

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "rejects unknown paths" do
    conn = Router.call(conn(:get, "/unknown"), Router.init(session: self()))

    assert conn.status == 404
  end
end
