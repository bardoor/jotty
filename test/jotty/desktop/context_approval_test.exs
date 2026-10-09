defmodule Jotty.Desktop.ContextApprovalTest do
  use ExUnit.Case, async: true

  alias Jotty.Desktop.ContextApproval

  test "accepts only a path signed by the Electron directory picker" do
    secret = "launch-secret"
    path = "/chosen/project"
    signature = :crypto.mac(:hmac, :sha256, secret, path)
    approval = Base.encode16(signature, case: :lower)

    assert ContextApproval.valid?(secret, path, approval)
    refute ContextApproval.valid?(secret, "/different/project", approval)
    refute ContextApproval.valid?(nil, path, approval)
  end
end
