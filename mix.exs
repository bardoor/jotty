defmodule Jotty.MixProject do
  use Mix.Project

  def project do
    [
      app: :jotty,
      version: "0.3.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
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
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4.5"},
      {:plug, "~> 1.20"},
      {:req, "~> 0.7.4"},
      {:websock_adapter, "~> 0.6.0"},
      {:websockex, "~> 0.5.1"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]
end
