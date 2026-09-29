defmodule Jotty.LiveAudioPacket do
  @moduledoc false

  @type source :: :system | :microphone
  @type failure_reason :: :conversion | :queue_overflow | :packet_output
  @type frame ::
          :ready
          | {:pcm, source(), binary()}
          | {:live_source_failed, source(), failure_reason()}
  @type protocol_error :: :invalid_packet

  @spec decode(binary()) :: {:ok, frame()} | {:error, protocol_error()}
  def decode(<<1>>), do: {:ok, :ready}
  def decode(<<2, pcm::binary>>), do: {:ok, {:pcm, :system, pcm}}
  def decode(<<3, pcm::binary>>), do: {:ok, {:pcm, :microphone, pcm}}
  def decode(<<4, 1, 1>>), do: {:ok, {:live_source_failed, :system, :conversion}}
  def decode(<<4, 1, 2>>), do: {:ok, {:live_source_failed, :system, :queue_overflow}}
  def decode(<<4, 1, 3>>), do: {:ok, {:live_source_failed, :system, :packet_output}}
  def decode(<<4, 2, 1>>), do: {:ok, {:live_source_failed, :microphone, :conversion}}
  def decode(<<4, 2, 2>>), do: {:ok, {:live_source_failed, :microphone, :queue_overflow}}
  def decode(<<4, 2, 3>>), do: {:ok, {:live_source_failed, :microphone, :packet_output}}
  def decode(_packet), do: {:error, :invalid_packet}
end
