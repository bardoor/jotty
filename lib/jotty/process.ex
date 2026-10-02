defmodule Jotty.Process do
  @moduledoc false

  @spec spawn_monitor((-> term())) :: {pid(), reference()}
  def spawn_monitor(function) do
    metadata = Logger.metadata()

    Kernel.spawn_monitor(fn ->
      Logger.metadata(metadata)
      function.()
    end)
  end
end
