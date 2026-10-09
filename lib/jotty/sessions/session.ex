defmodule Jotty.Sessions.Session do
  @moduledoc false

  use Jotty.Model

  alias Jotty.Sessions.{SessionContext, TranscriptChunk}

  @create_required_fields ~w(id title status started_at directory system_audio_path microphone_audio_path
aec_microphone_audio_path playback_audio_path transcript_path summary_path)a
  @create_optional_fields ~w(failure completed_at duration_ms)a
  @rename_required_fields ~w(title)a
  @rename_optional_fields ~w()a
  @transition_required_fields ~w(status completed_at duration_ms)a
  @transition_optional_fields ~w(failure)a

  schema "sessions" do
    field :title, :string
    field :status, Ecto.Enum, values: ~w(recording completed failed)a
    field :failure, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :directory, :string
    field :system_audio_path, :string
    field :microphone_audio_path, :string
    field :aec_microphone_audio_path, :string
    field :playback_audio_path, :string
    field :transcript_path, :string
    field :summary_path, :string

    has_many :transcript_chunks, TranscriptChunk
    has_many :contexts, SessionContext

    timestamps()
  end

  def create_changeset(session, attributes) do
    session
    |> cast(attributes, @create_required_fields ++ @create_optional_fields)
    |> validate_required(@create_required_fields)
    |> validate_title()
  end

  def rename_changeset(session, attributes) do
    session
    |> cast(attributes, @rename_required_fields ++ @rename_optional_fields)
    |> validate_required(@rename_required_fields)
    |> validate_title()
  end

  def transition_changeset(session, attributes) do
    session
    |> cast(attributes, @transition_required_fields ++ @transition_optional_fields)
    |> validate_required(@transition_required_fields)
  end

  defp validate_title(changeset) do
    changeset
    |> update_change(:title, fn
      title when is_binary(title) -> String.trim(title)
      title -> title
    end)
    |> validate_length(:title, min: 1, max: 120)
  end
end
