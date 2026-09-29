defmodule Jotty.LiveAudioPacketTest do
  use ExUnit.Case, async: true

  alias Jotty.LiveAudioPacket

  test "decodes every valid packet" do
    assert {:ok, :ready} = LiveAudioPacket.decode(<<1>>)
    assert {:ok, {:pcm, :system, <<1, 2>>}} = LiveAudioPacket.decode(<<2, 1, 2>>)
    assert {:ok, {:pcm, :microphone, <<3, 4>>}} = LiveAudioPacket.decode(<<3, 3, 4>>)

    for {source_byte, source} <- [{1, :system}, {2, :microphone}],
        {reason_byte, reason} <- [{1, :conversion}, {2, :queue_overflow}, {3, :packet_output}] do
      assert {:ok, {:live_source_failed, ^source, ^reason}} =
               LiveAudioPacket.decode(<<4, source_byte, reason_byte>>)
    end
  end

  test "rejects packets outside the native protocol" do
    assert {:error, :invalid_packet} = LiveAudioPacket.decode(<<>>)
    assert {:error, :invalid_packet} = LiveAudioPacket.decode(<<5>>)
    assert {:error, :invalid_packet} = LiveAudioPacket.decode(<<4, 3, 1>>)
  end
end
