defmodule Jotty.Session.Consumer do
  @moduledoc "A session message handler with explicit subscriptions."

  alias Jotty.Session.{Events, State}

  @callback subscriptions() :: [module()]
  @callback handle_message(Events.message(), State.t()) :: State.t()
end
