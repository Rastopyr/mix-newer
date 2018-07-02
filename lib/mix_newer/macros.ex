defmodule MixNewer.Macros do
  @moduledoc """
  This module defines macros for use in users' template scripts.
  """

  # Should be available in defs.exs
  defmacro flag(name, type) do
    quote do
      var!(flags) = Keyword.put(var!(flags), unquote(name), unquote(type))
    end
  end

  # Should be available in defs.exs
  defmacro param(name, value) do
    quote do
      Keyword.put(var!(user_config), unquote(name), unquote(value))
    end
  end

  # Should be available in init.exs
  defmacro select(template, options \\ []) do
    rename = Keyword.get(options, :rename, false)
    quote do
      var!(actions) = var!(actions) ++ [
        {:select, unquote(template), unquote(rename)}
      ]
    end
  end
end
