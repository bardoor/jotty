defmodule Jotty.Session.State do
  @moduledoc false

  alias Jotty.Session.{Assistant, Lifecycle, Presentation, Recording, Summary, Transcript, Transcription}

  @type t :: %__MODULE__{
          events: :queue.queue(Jotty.Session.Events.message()),
          lifecycle: Lifecycle.t(),
          recording: Recording.t(),
          transcription: Transcription.t(),
          transcript: Transcript.t(),
          assistant: Assistant.t(),
          summary: Summary.t(),
          presentation: Presentation.t()
        }

  @enforce_keys [:lifecycle, :recording, :transcription, :transcript, :assistant, :summary, :presentation]
  defstruct [
    :lifecycle,
    :recording,
    :transcription,
    :transcript,
    :assistant,
    :summary,
    :presentation,
    events: :queue.new()
  ]

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{
      lifecycle: Lifecycle.new(options),
      recording: Recording.new(options),
      transcription: Transcription.new(options),
      transcript: Transcript.new(options),
      assistant: Assistant.new(options),
      summary: Summary.new(options),
      presentation: Presentation.new(options)
    }
  end
end
