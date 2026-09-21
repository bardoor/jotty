defmodule Jotty.CLITest do
  use ExUnit.Case, async: false

  alias Jotty.CLI

  test "rejects every command except record" do
    assert {:error, :usage} = CLI.run([])
    assert {:error, :usage} = CLI.run(["unknown"])
  end

  test "reads the Soniox key from application configuration" do
    previous_key = Application.get_env(:jotty, :soniox_api_key)
    previous_environment_key = System.get_env("SONIOX_API_KEY")

    on_exit(fn ->
      restore_application_key(previous_key)
      restore_environment_key(previous_environment_key)
    end)

    Application.put_env(:jotty, :soniox_api_key, "configured-key")
    System.delete_env("SONIOX_API_KEY")

    assert {:error, {:native_recorder_not_found, _path}} = CLI.run(["record"])
  end

  defp restore_application_key(nil), do: Application.delete_env(:jotty, :soniox_api_key)
  defp restore_application_key(key), do: Application.put_env(:jotty, :soniox_api_key, key)

  defp restore_environment_key(nil), do: System.delete_env("SONIOX_API_KEY")
  defp restore_environment_key(key), do: System.put_env("SONIOX_API_KEY", key)
end
