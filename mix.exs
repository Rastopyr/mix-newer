defmodule MixNewer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mix_newer,
      version: "0.2.1",
      elixir: "~> 1.0",
      deps: deps()
    ]
  end

  def application do
    [applications: []]
  end

  defp deps do
    [
      {:dogma, ">= 0.1.15", only: [:dev, :test]},
    ]
  end
end
