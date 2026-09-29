defmodule Jotty.Session.RealtimeTranscriptionFailed do
  @moduledoc false

  alias Jotty.LiveAudioPacket
  @enforce_keys [:source, :reason]
  defstruct [:source, :reason]

  @type t :: %__MODULE__{source: LiveAudioPacket.source() | nil, reason: term()}
end
