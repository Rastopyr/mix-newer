defmodule MixNewer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mix_newer,
      version: "0.2.0",
      elixir: "~> 1.0",
    ]
  end

  def application do
    [applications: []]
  end
end
