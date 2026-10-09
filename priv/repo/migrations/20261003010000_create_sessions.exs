defmodule Jotty.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:title, :text, null: false)
      add(:status, :text, null: false)
      add(:failure, :text)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)
      add(:duration_ms, :integer)
      add(:directory, :text, null: false)
      add(:system_audio_path, :text, null: false)
      add(:microphone_audio_path, :text, null: false)
      add(:aec_microphone_audio_path, :text, null: false)
      add(:playback_audio_path, :text, null: false)
      add(:transcript_path, :text, null: false)
      add(:summary_path, :text, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:sessions, ~w(started_at)a))

    execute(
      """
      CREATE TRIGGER sessions_status_insert
      BEFORE INSERT ON sessions WHEN NEW.status NOT IN ('recording', 'completed', 'failed')
      BEGIN SELECT RAISE(ABORT, 'sessions_status'); END
      """,
      "DROP TRIGGER sessions_status_insert"
    )

    execute(
      """
      CREATE TRIGGER sessions_status_update
      BEFORE UPDATE OF status ON sessions WHEN NEW.status NOT IN ('recording', 'completed', 'failed')
      BEGIN SELECT RAISE(ABORT, 'sessions_status'); END
      """,
      "DROP TRIGGER sessions_status_update"
    )

    create table(:transcript_chunks) do
      add(:session_id, references(:sessions, type: :binary_id, on_delete: :delete_all), null: false)
      add(:position, :integer, null: false)
      add(:speaker, :text, null: false)
      add(:text, :text, null: false)
      add(:start_ms, :integer, null: false)
      add(:end_ms, :integer, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:transcript_chunks, ~w(session_id position)a))

    create table(:session_contexts) do
      add(:session_id, references(:sessions, type: :binary_id, on_delete: :delete_all), null: false)
      add(:context_id, references(:contexts, on_delete: :nilify_all))
      add(:position, :integer, null: false)
      add(:name, :text, null: false)
      add(:path, :text, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:session_contexts, ~w(session_id position)a))
  end
end
