defmodule Mix.Tasks.Newer do
  use Mix.Task

  require Logger

  @shortdoc "Create a new Mix project from template"

  @usage "mix newer -t <template> [overrides] <name> [template options]"

  @moduledoc """
  ## Usage

      #{@usage}

  The template can be a:

    * local directory
    * URL to a Git repository

  Any parameters used or defined in the template can be overriden on the
  command line. For example, the default parameter `APP_NAME` and
  user-defined parameter `some_name` can be overriden as follows:

      mix newer -t <template> -o APP_NAME=Othername -o some_name='foo bar' myapp

  """

  def run(args) do
    options = [
      strict: [template: :string, override: [:string, :keep]],
      aliases: [t: :template, o: :override],
    ]

    heads = OptionParser.parse_head(args, options)

    {name, template, overrides, rest} = case heads do
      {opts, [name | rest], []} ->
        template = Keyword.get(opts, :template, "default")
        kwds = Keyword.delete(opts, :template)
        overrides = Enum.map(kwds, fn {:override, val} -> val end)

        {name, template, overrides, rest}
      {_, _, [{opt, _}]} ->
        Mix.raise "Undefined option #{opt}"
      {_, [], _} ->
        Mix.raise "Usage: #{@usage}"
    end

    fetched_template = fetch_template(template, name)
    parsed_overrides = parse_overrides(overrides)

    instantiate_template(name, fetched_template, parsed_overrides, rest)

    Mix.shell.info [
      :green, "Successfully built ",
      :reset, name,
      :green, " from template."
    ]
  end

  defp fetch_template("default", _dest) do
    IO.puts "Using default template."
    IO.puts "(not implemented)"
    System.halt 1
  end

  defp fetch_template(template, dest) do
    is_git = String.ends_with?(template, ".git") or
      File.dir?(Path.join([template, ".git"]))

    cond do
      is_git ->
        Mix.SCM.Git.checkout(git: template, checkout: dest)

      String.starts_with?(template, "http") ->
        id = Base.encode16 :crypto.strong_rand_bytes(4)
        unique_name = "mix_newer_template_#{id}"
        tmp_path = Path.join(System.tmp_dir!, unique_name)

        :httpc.download_file(template, tmp_path)

      File.dir?(template) ->
        File.cp_r!(template, dest)
    end
    dest
  end

  defp parse_overrides(overrides) do
    overrides = Enum.map(overrides, fn str ->
      [opt_name, value] = String.split(str, "=")
      param_name = String.to_atom(opt_name)
      {param_name, value}
    end)


    Enum.into(overrides, %{})
  end

  defp instantiate_template(name, path, overrides, rest_args) do
    config = MixNewer.Config.default_config(name, overrides)

    File.cd!(path)
    {config, flags} = MixNewer.Eval.eval_defs(config, overrides, rest_args)
    actions = MixNewer.Eval.eval_init(config, flags)
    postprocess_file_hierarchy(config, actions)
  end

  defp postprocess_file_hierarchy(user_config, actions) do
    {files, template_files, directories} = get_files_and_directories(user_config)

    directories
    |> substitute_variables(user_config)

    files
    |> reject_auxilary_files
    |> substitute_variables(user_config)
    |> substitute_variables_in_files(user_config)

    cleanup postprocess_template_files(template_files, user_config, actions)
  end

  defp postprocess_template_files(paths, user_config, actions) do
    Enum.reduce(actions, paths, &process_action(&1, &2, user_config))
  end

  defp process_action({:select, template, rename}, paths, config) do
    template = substitute_variables_in_string(template, config)
    if path = Enum.find(paths, &(&1 == template <> "._template")) do
      new_path =
        if rename do
          path
          |> Path.dirname()
          |> Path.join(substitute_variables_in_string(rename, config))
          |> substitute_variables_in_string(config)
        else
          template
        end

      :ok = :file.rename(path, new_path)
      List.delete(paths, path)
    else
      Mix.raise "Template file '#{template<>"._template"}' not found"
    end
  end

  defp get_files_and_directories(config) do
    {files, dirs} = Enum.partition(Path.wildcard("**"), &File.regular?/1)
    template_files =
      files
      |> Enum.filter(&String.ends_with?(&1, "._template"))
      |> Enum.map(&substitute_variables_in_string(&1, config))
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
        case :file.rename(path, new_path) do
          :ok -> :ok
          { :error, errCode } -> { :error, errCode }
        end
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
      new_contents = path
      |> File.read!
      |> substitute_variables_in_string(config)

      File.write!(path, new_contents)
    end)
  end

  defp cleanup(rejected_templates) do
    [".git", "_template_config" | rejected_templates]
    |> Enum.each(&File.rm_rf!/1)
  end
end
