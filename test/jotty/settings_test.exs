defmodule Jotty.SettingsTest do
  use ExUnit.Case, async: false

  alias Jotty.Repo
  alias Jotty.Settings
  alias Jotty.Settings.{Context, Microphone, Setting}

  setup do
    reset_settings()
    on_exit(&reset_settings/0)
    :ok
  end

  test "persists the singleton desktop settings" do
    assert {:ok, _setting} = Settings.change_always_on_top(true)
    assert {:ok, _setting} = Settings.change_microphone("mic-1")

    snapshot = Settings.snapshot([%Microphone{id: "mic-1", name: "Desk Mic"}])
    assert snapshot.always_on_top
    assert snapshot.microphone_device_id == "mic-1"
    assert snapshot.microphone_available
    assert Repo.aggregate(Setting, :count) == 1
  end

  @tag :tmp_dir
  test "normalizes, orders, removes, and marks global contexts unavailable", %{tmp_dir: directory} do
    first = Path.join(directory, "first")
    second = Path.join(directory, "second")
    File.mkdir_p!(first)
    File.mkdir_p!(second)

    assert {:ok, first_context} = Settings.add_context(first)
    assert {:ok, second_context} = Settings.add_context(Path.join(second, "."))
    assert :ok = Settings.reorder_contexts([second_context.id, first_context.id])

    assert Enum.map(Settings.snapshot().contexts, & &1.name) == ["second", "first"]

    File.rmdir!(second)
    assert [%{path: ^second, available: false} | _] = Settings.snapshot().contexts

    assert {:error, {:context_directory_not_found, ^second}} =
             Settings.recording_configuration(Settings.snapshot())

    assert :ok = Settings.remove_context(second_context.id)
    assert [%{id: id, position: 0}] = Settings.snapshot().contexts
    assert id == first_context.id
  end

  @tag :tmp_dir
  test "rejects paths that were not selected as existing directories", %{tmp_dir: directory} do
    missing = Path.join(directory, "missing-context")
    assert {:error, {:context_directory_not_found, ^missing}} = Settings.add_context(missing)
  end

  test "rejects an unavailable persisted microphone before recording" do
    assert {:ok, _setting} = Settings.change_microphone("missing-mic")
    snapshot = Settings.snapshot([%Microphone{id: "other", name: "Other"}])

    refute snapshot.microphone_available

    assert {:error, {:microphone_device_unavailable, "missing-mic"}} =
             Settings.recording_configuration(snapshot)
  end

  defp reset_settings do
    Repo.delete_all(Context)
    setting = Repo.one!(Setting)

    {:ok, _setting} =
      setting
      |> Setting.changeset(%{always_on_top: false, microphone_device_id: nil})
      |> Repo.update()

    :ok
  end
end
