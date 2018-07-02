MixNewer
========

Generic project template generator for Mix.

This project implements a Mix task named `newer` which can take a specially
prepared file hierarchy and create scaffolding for a new project from it.


## Installation

Download the latest archive from the Releases page

```sh
$ mix archive.install https://github.com/Rastopyr/mix-newer/releases/download/alpha2/mix_newer-0.2.0.ez
```

or build from source as follows:

```sh
$ mix archive.build
$ mix archive.install
```


## Usage

Some examples:

```sh
# Build a project from Phoenix template, overriding the 'session_secret'
# parameter's value
$ mix newer
    -t https://github.com/alco/mix-phoenix-template.git
    -o session_secret=abc
    myphoenix

$ ls myphoenix
README.md config    lib       mix.exs   priv      test      web

$ ls myphoenix/lib
myphoenix.ex

# Build a project from Elixir template, passing the custom --sup flag defined
# by it
$ mix newer -t https://github.com/alco/mix-elixir-template.git myapp --sup

$ ls myapp
README.md config    lib       mix.exs   test

$ ls myapp/test
myapp_test.exs  test_helper.exs
```


## How to create a template

A template is essentially an arbitrary file hierarchy that will be copied
verbatim at the destination path and postprocessed in some way.

When a template is instantiated, all occurrences of strings that look like
`{{parameter_name}}` will be replaced by the values of corresponding
parameters. By default, `mix newer` defines the following parameters:

  * `APP_NAME` – it takes as its value the directory name passed on the command
    line

  * `MODULE_NAME` – a "camelized" version of `APP_NAME` used to name user
    modules in the template

  * `MIX_VERSION` – full version (e.g. `1.0.0`) of Mix (which is the same as
    Elixir version) with which the template is instantiated

  * `MIX_VERSION_SHORT` – shortened version (e.g. `1.0`) recommended for use in
    Elixir version requirement in `mix.exs`


### User scripts

To add custom parameters or flags, a file named `defs.exs` should be placed
under the special `_template_config` directory inside the template. Certain
files in this directory will be evaluated during template instantiation and
the directory will be removed in the end.

An example `defs.exs` file might look as follows:

```elixir
flag :custom, :string

param :my_param, config[:APP_NAME]<>"tail"
```

The newly defined parameter can be used in any file as `{{my_param}}`. The
custom flag can be passed on the command line as `--custom value` or
`--custom='longer string'`.

After defining custom flags and parameters, `mix newer` will look for
`_template_config/init.exs` script and execute it if present. The script can
contain any valid Elixir code. It will have two dicts available:

  * `flags` will contain the values of custom flags passed by the user on the
    command line

  * `config` will contain all parameters and their values (whether builtin or
    specified on the command line)

Additionally, the init script will also have `select` macro autoimported which
can be used to selectively choose one of special template files described
below.


## Special template files

Files with names ending in `._template` won't be copied into the destination
directory unless picked explicitly. To pick such a file, the `select` macro
should be used. For instance, if there are two such files under the `lib/`
directory named `option_1.ex._template` and `option_2.ex._template`, one of
them can be picked in `init.exs` as follows:

```elixir
# Decide which file to pick based on the value of our a custom flag
if flags[:custom] == "second" do
  select "lib/option_2.ex", rename: "{{APP_NAME}}.ex"
else
  select "lib/option_1.ex", rename: "{{APP_NAME}}.ex"
end
```

The picked file will be kept under the `lib/` directory with a new name, and
the other file will be removed before the template instantiation completes.

If `rename` option isn't set, default name will be kept.

### Examples

See the following examples for reference:

  * https://github.com/alco/mix-elixir-template
  * https://github.com/alco/mix-phoenix-template


## License

This software is licensed under [the MIT license](LICENSE).
