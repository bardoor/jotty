defmodule Jotty.Repo.Migrations.UseUuidPrimaryKeys do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    uuid =
      "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || " <>
        "lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || " <>
        "lower(hex(randomblob(6)))"

    execute("PRAGMA foreign_keys = OFF")
    execute("DROP TRIGGER settings_singleton_insert")
    execute("DROP TRIGGER settings_singleton_update")

    execute("CREATE TABLE context_id_map (old_id INTEGER PRIMARY KEY, new_id TEXT NOT NULL)")
    execute("INSERT INTO context_id_map (old_id, new_id) SELECT id, #{uuid} FROM contexts")

    execute("""
    CREATE TABLE settings_new (
      id TEXT PRIMARY KEY NOT NULL,
      always_on_top INTEGER NOT NULL DEFAULT 0,
      microphone_device_id TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO settings_new (id, always_on_top, microphone_device_id, inserted_at, updated_at)
    SELECT #{uuid}, always_on_top, microphone_device_id, inserted_at, updated_at FROM settings
    """)

    execute("""
    CREATE TABLE contexts_new (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      path TEXT NOT NULL,
      position INTEGER NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO contexts_new (id, name, path, position, inserted_at, updated_at)
    SELECT context_id_map.new_id, contexts.name, contexts.path, contexts.position,
           contexts.inserted_at, contexts.updated_at
    FROM contexts
    JOIN context_id_map ON context_id_map.old_id = contexts.id
    """)

    execute("""
    CREATE TABLE transcript_chunks_new (
      id TEXT PRIMARY KEY NOT NULL,
      session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      speaker TEXT NOT NULL,
      text TEXT NOT NULL,
      start_ms INTEGER NOT NULL,
      end_ms INTEGER NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO transcript_chunks_new
      (id, session_id, position, speaker, text, start_ms, end_ms, inserted_at, updated_at)
    SELECT #{uuid}, session_id, position, speaker, text, start_ms, end_ms, inserted_at, updated_at
    FROM transcript_chunks
    """)

    execute("""
    CREATE TABLE session_contexts_new (
      id TEXT PRIMARY KEY NOT NULL,
      session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      context_id TEXT REFERENCES contexts_new(id) ON DELETE SET NULL,
      position INTEGER NOT NULL,
      name TEXT NOT NULL,
      path TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO session_contexts_new
      (id, session_id, context_id, position, name, path, inserted_at, updated_at)
    SELECT #{uuid}, session_contexts.session_id, context_id_map.new_id, session_contexts.position,
           session_contexts.name, session_contexts.path,
           session_contexts.inserted_at, session_contexts.updated_at
    FROM session_contexts
    LEFT JOIN context_id_map ON context_id_map.old_id = session_contexts.context_id
    """)

    execute("DROP TABLE session_contexts")
    execute("DROP TABLE transcript_chunks")
    execute("DROP TABLE contexts")
    execute("DROP TABLE settings")
    execute("ALTER TABLE settings_new RENAME TO settings")
    execute("ALTER TABLE contexts_new RENAME TO contexts")
    execute("ALTER TABLE transcript_chunks_new RENAME TO transcript_chunks")
    execute("ALTER TABLE session_contexts_new RENAME TO session_contexts")
    execute("DROP TABLE context_id_map")

    create(unique_index(:contexts, ~w(path)a))
    create(index(:contexts, ~w(position)a))
    create(unique_index(:transcript_chunks, ~w(session_id position)a))
    create(unique_index(:session_contexts, ~w(session_id position)a))

    execute("""
    CREATE TRIGGER settings_singleton_insert
    BEFORE INSERT ON settings WHEN EXISTS (SELECT 1 FROM settings)
    BEGIN SELECT RAISE(ABORT, 'settings_singleton'); END
    """)

    execute("PRAGMA foreign_keys = ON")
  end

  def down do
    raise "UUID primary keys cannot be converted back to integer identities"
  end
end
