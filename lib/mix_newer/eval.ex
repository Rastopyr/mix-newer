defmodule MixNewer.Eval do
  @moduledoc """
  Functions related to evaluating user scripts in templates.
  """

  def eval_defs(config, overrides, args) do
    path = "_template_config/defs.exs"
    if File.exists?(path) do
      do_eval_defs(path, config, overrides, args)
    else
      {config, []}
    end
  end

  defp do_eval_defs(path, config, overrides, args) do
    vars = [config: config, user_config: [], flags: []]
    bindings = eval_script(path, :defs, vars)

    flags = Keyword.fetch!(bindings, :flags)
    user_flags = case OptionParser.parse(args, strict: flags) do
      {opts, [], []} ->
        opts
      {_, [arg | _], _} ->
        Mix.raise "Extraneous argument: #{arg}"
      {_, _, [{opt, _}]} ->
        Mix.raise "Undefine user option #{opt}"
    end

    bindings_config = bindings
    |> Keyword.fetch!(:user_config)
    |> Enum.into(%{})

    user_config = config
    |> Map.merge(bindings_config)
    |> MixNewer.Config.apply_overrides(overrides)

    {user_config, user_flags}
  end

  def eval_init(config, flags) do
    path = "_template_config/init.exs"
    if File.exists?(path) do
      vars = [config: config, flags: flags, actions: []]

      path
      |> eval_script(:init, vars)
      |> Keyword.fetch!(:actions)
    else
      []
    end
  end

  defp eval_script(path, env_id, vars) do
    code = path
    |> File.read!
    |> Code.string_to_quoted!
    env = make_env_for(env_id)
    {_, bindings} = Code.eval_quoted(code, vars, env)
    bindings
  end

  defp make_env_for(:defs) do
    import MixNewer.Macros, only: [flag: 2, param: 2], warn: false
    __ENV__
  end

  defp make_env_for(:init) do
    import MixNewer.Macros, only: [select: 1, select: 2], warn: false
    __ENV__
  end
end
