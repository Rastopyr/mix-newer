defmodule MixNewer.Macros do
  # This one is available in flags.exs
  defmacro flag(name, type) do
    quote do
      var!(flags) = Keyword.put(var!(flags), unquote(name), unquote(type))
    end
  end


  ## The following macros are available in init.exs

  defmacro param(name, value) do
    quote do
      var!(user_config) = Keyword.put(var!(user_config), unquote(name), unquote(value))
    end
  end

  defmacro select(template, options) do
    rename = Keyword.get(options, :rename, false)
    quote do
      var!(actions) = var!(actions) ++ [{:select, unquote(template), unquote(rename)}]
    end
  end
end

defmodule Mix.Tasks.Newer do
  use Mix.Task

  @shortdoc "Create a new mix project from template"

  @moduledoc """
  ## Usage

      mix newer -t <template> [options] <name>

  The template can be one of:

    * local directory
    * URL to a repository
    * URL to a zip or tar archive that will be fetched and unpacked

  Any parameters used or defined in the template can be overriden on the
  command line. For example, the default parameter `MODULE_NAME` and
  user-defined parameter `some_name` can be overriden as follows:

      mix newer -t <template> -o MODULE_NAME=Othername myapp

  """

  def run(args) do
    options = [
      strict: [template: :string, override: [:string, :keep]],
      aliases: [t: :template, o: :override],
    ]
    {name, template, overrides, rest} =
      case OptionParser.parse_head(args, options) do
        {opts, [name|rest], []} ->
          template = Keyword.get(opts, :template, "default")
          overrides =
            Keyword.delete(opts, :template)
            |> Enum.map(fn {:override, val} -> val end)
          {name, template, overrides, rest}
        {_, _, [{opt, _}]} ->
          Mix.raise "Undefined option #{opt}"
        {_, [], _} ->
          Mix.raise "Usage: mix newer -t <template> [overrides] <name> [template options]"
      end

    instantiate_template(name, fetch_template(template, name), parse_overrides(overrides), rest)
  end

  defp fetch_template("default", _dest) do
    IO.puts "Using default template."
    System.halt 0
  end

  defp fetch_template(template, dest) do
    cond do
      String.ends_with?(template, ".git") or File.dir?(Path.join([template, ".git"])) ->
        Mix.SCM.Git.checkout(git: template, dest: dest)

      String.starts_with?(template, "http") ->
        id = :crypto.rand_bytes(4) |> Base.encode16
        unique_name = "mix_newer_template_#{id}"
        tmp_path = Path.join(System.tmp_dir!, unique_name)

        # FIXME
        :httpc.download_file(template, tmp_path)

      File.dir?(template) ->
        File.cp_r!(template, dest)
    end
    dest
  end

  @builtin_params [
      :APP_NAME,
      :MODULE_NAME,
      :MIX_VERSION,
      :MIX_VERSION_SHORT,
  ]

  defp parse_overrides(overrides) do
    Enum.map(overrides, fn str ->
      [opt_name, value] = String.split(str, "=")
      param_name = String.to_atom(opt_name)
      {param_name, value}
    end)
    |> Enum.into(%{})
  end

  defp eval_script(path, env_id, vars) do
    code = File.read!(path) |> Code.string_to_quoted!
    env = make_env_for(env_id)
    {_, bindings} = Code.eval_quoted(code, vars, env)
    bindings
  end

  defp instantiate_template(name, path, overrides, rest_args) do
    config = %{
      APP_NAME: Dict.get(overrides, :APP_NAME, name),
      MODULE_NAME: Dict.get(overrides, :MODULE_NAME, Mix.Utils.camelize(name)),
      MIX_VERSION: Dict.get(overrides, :MIX_VERSION, System.version),
      MIX_VERSION_SHORT: Dict.get(overrides, :MIX_VERSION_SHORT, Path.rootname(System.version)),
    }

    File.cd!(path)
    {config, flags} = eval_defs(config, overrides, rest_args)
    actions = eval_init(config, flags)
    postprocess_file_hierarchy(config, actions)
  end

  defp eval_defs(config, overrides, args) do
    vars = [config: config, user_config: [], flags: []]
    bindings = eval_script("_template_config/defs.exs", :defs, vars)

    flags = Keyword.fetch!(bindings, :flags)
    user_flags = case OptionParser.parse(args, strict: flags) do
      {opts, [], []} ->
        opts
      {_, [arg|_], _} ->
        Mix.raise "Extraneous argument: #{arg}"
      {_, _, [{opt, _}]} ->
        Mix.raise "Undefine user option #{opt}"
    end

    user_config =
      config
      |> Map.merge(Keyword.fetch!(bindings, :user_config) |> Enum.into(%{}))
      |> apply_overrides(overrides)

    {user_config, user_flags}
  end

  defp eval_init(config, flags) do
    vars = [config: config, flags: flags, actions: []]
    eval_script("_template_config/init.exs", :init, vars)
    |> Keyword.fetch!(:actions)
  end

  defp make_env_for(:defs) do
    import MixNewer.Macros, only: [flag: 2, param: 2], warn: false
    __ENV__
  end

  defp make_env_for(:init) do
    import MixNewer.Macros, only: [select: 2], warn: false
    __ENV__
  end

  defp apply_overrides(config, overrides) do
    Enum.each(overrides, fn {k,_} ->
      unless Enum.any?(config, &match?({^k,_}, &1)) do
        Mix.raise "Undefined parameter #{k}"
      end
    end)

    Enum.map(config, fn {k,v} ->
      {k, Dict.get(overrides, k, v)}
    end) |> Enum.into(%{})
  end

  defp postprocess_file_hierarchy(user_config, actions) do
    {files, template_files, _directories} = get_files_and_directories()

    files
    |> reject_auxilary_files
    |> substitute_variables(user_config)
    |> substitute_variables_in_files(user_config)

    rejected_templates = postprocess_template_files(template_files, user_config, actions)
    cleanup(rejected_templates)
  end

  defp postprocess_template_files(paths, user_config, actions) do
    Enum.reduce(actions, paths, &process_action(&1, &2, user_config))
  end

  defp process_action({:select, template, rename}, paths, config) do
    new_name = substitute_variables_in_string(rename, config)
    if path = Enum.find(paths, &(&1 == template<>"._template")) do
      new_path = Path.join([Path.dirname(path), new_name])
      :ok = :file.rename(path, new_path)
      List.delete(paths, path)
    else
      Mix.raise "Template file '#{template<>"._template"}' not found"
    end
  end

  defp get_files_and_directories() do
    {files, dirs} = Path.wildcard("**") |> Enum.partition(&File.regular?/1)
    template_files = Enum.filter(files, &String.ends_with?(&1, "._template"))
    {files, template_files, dirs}
  end

  defp reject_auxilary_files(paths) do
    Enum.reject(paths, &String.starts_with?(&1, "_template_config"))
  end

  defp substitute_variables(paths, config) do
    paths
    |> Enum.map(fn path ->
      new_path = substitute_variables_in_string(path, config)
      if path != new_path do
        :ok = :file.rename(path, new_path)
      end
      new_path
    end)
  end

  defp substitute_variables_in_string(string, config) do
    Enum.reduce(config, string, fn {k, v}, string ->
      String.replace(string, "{{#{k}}}", v)
    end)
  end

  defp substitute_variables_in_files(files, config) do
    files
    |> Enum.each(fn path ->
      new_contents = path |> File.read! |> substitute_variables_in_string(config)
      File.write!(path, new_contents)
    end)
  end

  defp cleanup(rejected_templates) do
    [".git", "_template_config" | rejected_templates]
    |> Enum.each(&File.rm_rf!/1)
  end
end
