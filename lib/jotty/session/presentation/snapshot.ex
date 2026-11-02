defmodule Jotty.Session.Presentation.Snapshot do
  @moduledoc false

  alias Jotty.Session.Events.{HermesActivityObserved, TranscriptionPreviewed, UtteranceCompleted}
  alias Jotty.Tasks.Card

  @type t :: %__MODULE__{
          type: :snapshot,
          status: Jotty.Session.Presentation.status(),
          utterances: [UtteranceCompleted.t()],
          preview: TranscriptionPreviewed.t() | nil,
          realtime_error: String.t() | nil,
          summary: String.t() | nil,
          activities: [HermesActivityObserved.t()],
          task_cards: [Card.t()],
          task_search_query: String.t() | nil,
          task_error: String.t() | nil,
          recording_directory: Path.t() | nil
        }

  defstruct type: :snapshot,
            status: :idle,
            utterances: [],
            preview: nil,
            realtime_error: nil,
            summary: nil,
            activities: [],
            task_cards: [],
            task_search_query: nil,
            task_error: nil,
            recording_directory: nil
end
