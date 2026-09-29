defmodule Jotty.Session.TranscriptionPreviewed do
  @moduledoc false

  alias Jotty.LiveAudioPacket
  alias Jotty.STT.TranscriptionChunk

  @enforce_keys [:source, :chunks]
  defstruct [:source, :chunks]

  @type t :: %__MODULE__{source: LiveAudioPacket.source(), chunks: [TranscriptionChunk.t(), ...]}
end
