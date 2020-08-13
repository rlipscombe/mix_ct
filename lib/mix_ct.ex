defmodule Mix.Tasks.Ct do
  use Mix.Task

  import Mix.Generator

  @shortdoc "Run Common Test suites"

  @moduledoc """
  Runs the Common Test suites for a project.

  Usage:

      MIX_ENV=test mix do compile, ct

  This task assumes that MIX_ENV=test causes your Erlang project to define
  the `TEST` macro, and to add "test" to the `erlc_paths` option.

  ## Command line options

    * `--surefire` - enables Surefire-compatible XML output
    * `--cover` - exports coverage data. See below.

  ## Coverage

  In order to get coverage data, you need to compile with coverage enabled:

      MIX_ENV=test mix do compile --cover --force, ct --cover
  """

  @recursive true
  @preferred_cli_env :test

  def run, do: run([])

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [surefire: :boolean, cover: :boolean])

    Mix.shell().print_app()

    Mix.Task.run("loadpaths")

    project = Mix.Project.config()
    appname = project[:app]

    # ".../_build/<env>/lib/<app>"
    app_path = Mix.Project.app_path()
    # ".../_build/<env>/lib/<app>/ebin"
    ebin_path = Path.join([app_path, "ebin"])

    # Ensure that 'ebin' is in the code search path; if the app isn't mentioned
    # in a dependency, it doesn't get added by default.
    Code.append_path(ebin_path)

    # ".../_build/<env>"
    build_path = Mix.Project.build_path()
    lib_path = Path.join(build_path, "lib")
    ebin_paths = Path.wildcard(Path.join([lib_path, "*", "ebin"]))
    log_dir = Path.join(build_path, "logs")

    # relative to cwd
    test_dir = "test"

    if File.exists?(test_dir) do
      File.mkdir_p!(log_dir)

      # Symlink each _data/ directory into the 'ebin' directory.
      for data_dir <- Path.wildcard(Path.join(test_dir, "*_data")) do
        link_dst = Path.join(ebin_path, Path.basename(data_dir))
        link_src = Path.expand(data_dir)

        case Mix.Utils.symlink_or_copy(link_src, link_dst) do
          {:ok, _paths} ->
            :ok

          :ok ->
            :ok
            # otherwise, fail with a case clause error
        end
      end

      ct_cmd =
        ["ct_run", "-no_auto_compile", "-noinput", "-abort_if_missing_suites", "-pa"] ++
          ebin_paths ++ ["-dir", test_dir, "-logdir", log_dir]

      ct_cmd =
        if opts[:surefire] do
          ct_cmd ++ ["-ct_hooks", "cth_surefire"]
        else
          ct_cmd
        end

      ct_cmd =
        if opts[:cover] do
          cover_spec = Path.join([app_path, "ct.cover.spec"])

          assigns = [
            app: appname,
            coverdata: Path.join([app_path, "ct.coverdata"])
          ]

          create_file(cover_spec, cover_spec_template(assigns), force: true, quiet: true)
          ct_cmd ++ ["-cover", cover_spec]
        else
          ct_cmd
        end

      app_config_src = Path.join(test_dir, "app.config.src")
      app_config = Path.join(test_dir, "app.config")

      if File.exists?(app_config_src) do
        envsubst(app_config_src, app_config)
      end

      ct_cmd =
        if File.exists?(app_config) do
          ct_cmd ++ ["-erl_args", "-config", app_config]
        else
          ct_cmd
        end

      case Mix.shell().cmd(Enum.join(ct_cmd, " ")) do
        0 -> :ok
        _status -> Mix.raise("One or more tests failed.")
      end
    end
  end

  defp envsubst(source, destination) do
    content = File.read!(source)

    # Get a list of the environment variables that need replacing.
    vars = Regex.scan(~R/\${(.+)}/U, content)

    f = fn [p, v], c ->
      case System.get_env(v) do
        nil ->
          warn("#{source}: env var #{v} not found")
          String.replace(c, p, "")

        r ->
          String.replace(c, p, r)
      end
    end

    content = List.foldl(vars, content, f)

    File.write!(destination, content)
  end

  defp warn(message) do
    Mix.shell().info([:yellow, message, :reset])
  end

  embed_template(:cover_spec, """
  {incl_app, '<%= @app %>', details}.
  {export, "<%= @coverdata %>"}.
  """)
end
