defmodule Jotty.Session.Server do
  @moduledoc "Serializes typed session messages and stores their resulting state."

  use GenServer

  alias Jotty.Session.Events.{
    ClientAttached,
    ProcessExited,
    SessionTerminating,
    StartRequested,
    StopRequested,
    TranscriptionTimeout
  }

  alias Jotty.Session.{Events, Presentation, State}
  alias Jotty.Session.Presentation.Snapshot

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @spec publish(pid(), Events.message()) :: :ok
  def publish(server, message), do: GenServer.cast(server, {:message, message})

  @spec start_recording(pid()) :: :ok
  def start_recording(server), do: GenServer.call(server, {:message, %StartRequested{}})

  @spec stop_recording(pid()) :: :ok
  def stop_recording(server), do: GenServer.call(server, {:message, %StopRequested{}})

  @spec attach(pid(), pid()) :: Snapshot.t()
  def attach(server, client), do: GenServer.call(server, {:attach, client})

  @impl GenServer
  def init(options) do
    Logger.metadata(session_id: inspect(self()))
    {:ok, State.new(options)}
  end

  @impl GenServer
  def handle_call({:message, message}, _from, state) do
    {:reply, :ok, Events.dispatch(state, message)}
  end

  def handle_call({:attach, client}, _from, state) do
    state = Events.dispatch(state, %ClientAttached{client: client})
    {:reply, Presentation.snapshot(state), state}
  end

  @impl GenServer
  def handle_cast({:message, message}, state) do
    {:noreply, Events.dispatch(state, message)}
  end

  @impl GenServer
  def handle_info({:DOWN, reference, :process, pid, reason}, state) do
    message = %ProcessExited{reference: reference, pid: pid, reason: reason}
    {:noreply, Events.dispatch(state, message)}
  end

  def handle_info(%TranscriptionTimeout{} = message, state) do
    {:noreply, Events.dispatch(state, message)}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Events.dispatch(state, %SessionTerminating{})
    :ok
  end
end
