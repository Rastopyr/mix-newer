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

  defp instantiate_template(name, path, overrides, rest_args) do
    File.cd!(path)

    flag_code = File.read!("_template_config/flags.exs")
    env = make_env_for(:flags)
    {_, bindings} =
      Code.string_to_quoted!(flag_code)
      |> Code.eval_quoted([flags: []], env)

    flags = Keyword.fetch!(bindings, :flags)

    user_flags = case OptionParser.parse(rest_args, strict: flags) do
      {opts, [], []} ->
        opts
      {_, [arg|_], _} ->
        Mix.raise "Extraneous argument: #{arg}"
      {_, _, [{opt, _}]} ->
        Mix.raise "Undefine user option #{opt}"
    end

    config = %{
      APP_NAME: Dict.get(overrides, :APP_NAME, name),
      MODULE_NAME: Dict.get(overrides, :MODULE_NAME, Mix.Utils.camelize(name)),
      MIX_VERSION: Dict.get(overrides, :MIX_VERSION, System.version),
      MIX_VERSION_SHORT: Dict.get(overrides, :MIX_VERSION_SHORT, Path.rootname(System.version)),
    }

    init_code = File.read!("_template_config/init.exs")
    env = make_env_for(:init)
    {_, bindings} =
      Code.string_to_quoted!(init_code)
      |> Code.eval_quoted([config: config, user_config: [], actions: [], flags: user_flags], env)
    user_config =
      config
      |> Map.merge(Keyword.fetch!(bindings, :user_config) |> Enum.into(%{}))
      |> apply_overrides(overrides)

    IO.puts "actions"
    IO.inspect Keyword.fetch!(bindings, :actions)

    postprocess_file_hierarchy(user_config)
  end

  defp make_env_for(:flags) do
    import MixNewer.Macros, only: [flag: 2], warn: false
    __ENV__
  end

  defp make_env_for(:init) do
    import MixNewer.Macros, only: [param: 2, select: 2], warn: false
    __ENV__
  end

  defp apply_overrides(config, overrides) do
    Enum.map(config, fn {k,v} ->
      {k, Dict.get(overrides, k, v)}
    end) |> Enum.into(%{})
  end

  defp postprocess_file_hierarchy(user_config) do
    {files, _directories} = get_files_and_directories()

    new_files =
      files
      |> reject_auxilary_files
      |> substitute_variables(user_config)

    substitute_variables_in_files(new_files, user_config)

    cleanup()
  end

  defp get_files_and_directories() do
    Path.wildcard("**") |> Enum.partition(&File.regular?/1)
  end

  defp reject_auxilary_files(paths) do
    paths -- ["init_template.exs"]
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

  defp cleanup() do
    [".git", "init_template.exs"]
    |> Enum.each(&File.rm_rf!/1)
  end
end
