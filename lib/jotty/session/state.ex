defmodule Jotty.Session.State do
  @moduledoc false

  alias Jotty.Session.{Insights, Lifecycle, Presentation, Recording, Summary, Tasks, Transcript, Transcription}

  @type t :: %__MODULE__{
          events: :queue.queue(Jotty.Session.Events.message()),
          lifecycle: Lifecycle.t(),
          recording: Recording.t(),
          transcription: Transcription.t(),
          transcript: Transcript.t(),
          insights: Insights.t(),
          tasks: Tasks.t(),
          summary: Summary.t(),
          presentation: Presentation.t()
        }

  @enforce_keys ~w(lifecycle recording transcription transcript insights tasks summary presentation)a
  defstruct ~w(lifecycle recording transcription transcript insights tasks summary presentation)a ++
              [events: :queue.new()]

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{
      lifecycle: %Lifecycle{},
      recording: Recording.new(options),
      transcription: Transcription.new(options),
      transcript: %Transcript{},
      insights: %Insights{},
      tasks: Tasks.new(options),
      summary: Summary.new(options),
      presentation: Presentation.new(options)
    }
  end
end
