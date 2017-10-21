defmodule MixNewer.Config do
  @moduledoc """
  Functions related to defining and updating user config.
  """

  def default_config(name, overrides) do
    root = Path.rootname(System.version)

    %{
      APP_NAME: Dict.get(overrides, :APP_NAME, name),
      MODULE_NAME: Dict.get(overrides, :MODULE_NAME, Macro.camelize(name)),
      MIX_VERSION: Dict.get(overrides, :MIX_VERSION, System.version),
      MIX_VERSION_SHORT: Dict.get(overrides, :MIX_VERSION_SHORT, root),
    }
  end

  def apply_overrides(config, overrides) do
    Enum.each(overrides, fn {k,_} ->
      unless Enum.any?(config, &match?({^k,_}, &1)) do
        Mix.raise "Undefined parameter #{k}"
      end
    end)

    Enum.into Enum.map(config, fn {k,v} ->
      {k, Dict.get(overrides, k, v)}
    end), (%{})
  end
end
