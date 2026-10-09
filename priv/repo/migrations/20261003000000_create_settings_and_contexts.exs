defmodule Jotty.Repo.Migrations.CreateSettingsAndContexts do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:always_on_top, :boolean, null: false, default: false)
      add(:microphone_device_id, :text)

      timestamps(type: :utc_datetime_usec)
    end

    execute(
      """
      CREATE TRIGGER settings_singleton_insert
      BEFORE INSERT ON settings WHEN NEW.id != 1
      BEGIN SELECT RAISE(ABORT, 'settings_singleton'); END
      """,
      "DROP TRIGGER settings_singleton_insert"
    )

    execute(
      """
      CREATE TRIGGER settings_singleton_update
      BEFORE UPDATE OF id ON settings WHEN NEW.id != 1
      BEGIN SELECT RAISE(ABORT, 'settings_singleton'); END
      """,
      "DROP TRIGGER settings_singleton_update"
    )

    execute(
      "INSERT INTO settings (id, always_on_top, inserted_at, updated_at) " <>
        "VALUES (1, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
      "DELETE FROM settings WHERE id = 1"
    )

    create table(:contexts) do
      add(:name, :text, null: false)
      add(:path, :text, null: false)
      add(:position, :integer, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:contexts, ~w(path)a))
    create(index(:contexts, ~w(position)a))
  end
end
