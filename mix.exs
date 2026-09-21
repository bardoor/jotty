defmodule Jotty.MixProject do
  use Mix.Project

  def project do
    [
      app: :jotty,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Jotty.CLI]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:jason, "~> 1.4.5"},
      {:plug, "~> 1.18", only: :test},
      {:req, "~> 0.7.4"}
    ]
  end
end
