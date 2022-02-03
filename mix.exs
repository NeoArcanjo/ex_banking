defmodule ExBanking.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_banking,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExBanking.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Handle money
      {:money, "~> 1.9"},
      # Static analysis and test support
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.18.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.10", only: [:dev, :test]}
    ]
  end
end
