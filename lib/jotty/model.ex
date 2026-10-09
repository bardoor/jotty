defmodule Jotty.Model do
  @moduledoc false

  defmacro __using__(_options) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]

      @type t() :: %__MODULE__{}
    end
  end
end
