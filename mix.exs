defmodule MixNewer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mix_newer,
      version: "0.0.1",
      elixir: "~> 0.15"
    ]
  end

  def application do
    [applications: []]
  end
end
