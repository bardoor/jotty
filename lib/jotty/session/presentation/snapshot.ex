defmodule Jotty.Session.Presentation.Snapshot do
  @moduledoc false

  alias Jotty.Session.Events.{TranscriptionPreviewed, UtteranceCompleted}

  @type t :: %__MODULE__{
          type: :snapshot,
          status: Jotty.Session.Presentation.status(),
          utterances: [UtteranceCompleted.t()],
          preview: TranscriptionPreviewed.t() | nil,
          realtime_error: String.t() | nil,
          summary: String.t() | nil,
          recording_directory: Path.t() | nil
        }

  defstruct type: :snapshot,
            status: :idle,
            utterances: [],
            preview: nil,
            realtime_error: nil,
            summary: nil,
            recording_directory: nil
end
