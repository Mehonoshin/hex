defmodule Hex.Registry do
  @registry_tid :registry_tid
  @versions     [1, 2]

  def start(opts \\ []) do
    unless match?({ :ok, _ }, :application.get_env(:hex, @registry_tid)) do
      path = opts[:registry_path] || path()

      case :ets.file2tab(List.from_char_data!(path)) do
        { :ok, tid } ->
          :application.set_env(:hex, @registry_tid, tid)
          check_version(tid)

        { :error, reason } ->
          raise Mix.Error, message: "Failed to open hex registry file (#{inspect reason})"
      end
    end
  end

  def stop do
    case :application.get_env(:hex, @registry_tid) do
      { :ok, tid } ->
        :ets.delete(tid)
        :application.unset_env(:hex, @registry_tid)
        true
      :undefined ->
        false
    end
  end

  def path do
    Path.join(Mix.Utils.mix_home, "hex.ets")
  end

  def info_installs do
    case :ets.lookup(get_tid(), :"$$installs$$") do
      [{ :"$$installs$$", [versions|_] }] ->
        if version = latest_version(versions) do
          Mix.shell.error("A new Hex version is available (v#{version}), please update with `mix hex.local`")
        end
      _ ->
        :ok
    end
  end

  def stat do
    fun = fn
      { { package, version }, _ }, { packages, releases }
          when is_binary(package) and is_binary(version) ->
        { packages, releases + 1 }
      { package, _ }, { packages, releases } when is_binary(package) ->
        { packages + 1, releases }
      _, acc ->
        acc
    end

    :ets.foldl(fun, { 0, 0 }, get_tid())
  end

  def search(term) do
    fun = fn
      { package, list }, packages when is_binary(package) and is_list(list) ->
        if String.contains?(package, term) do
          [package|packages]
        else
          packages
        end
      _, packages ->
        packages
    end

    :ets.foldl(fun, [], get_tid())
    |> Enum.reverse
    |> Enum.sort
  end

  def exists?(package) do
    !! get_versions(package)
  end

  def exists?(package, version) do
    versions = get_versions(package)
    !! (versions && version in versions)
  end

  def get_versions(package) do
    case :ets.lookup(get_tid(), package) do
      [] -> nil
      [{ ^package, [versions|_] }] when is_list(versions) -> versions
      [{ ^package, versions }] -> versions
    end
  end

  def get_deps(package, version) do
    case :ets.lookup(get_tid(), { package, version }) do
      [] -> nil
      [{{^package, ^version}, [deps|_]}] when is_list(deps) -> deps
      [{{^package, ^version}, deps}] -> deps
    end
  end

  defp get_tid do
    { :ok, tid } = :application.get_env(:hex, @registry_tid)
    tid
  end

  defp check_version(tid) do
    case :ets.lookup(tid, :"$$version$$") do
      [{ :"$$version$$", version }] when version in @versions ->
        :ok
      _ ->
        raise Mix.Error,
          message: "The registry file version is not supported. " <>
                   "Try updating Hex with `mix local.hex`."
    end
  end

  defp latest_version(versions) do
    current_elixir = System.version
    current_hex    = Hex.version

    versions
    |> Enum.filter(fn {hex, _} -> Version.compare(hex, current_hex) == :gt end)
    |> Enum.filter(fn {_, elixir} -> Version.compare(elixir, current_elixir) != :gt end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort(&(Version.compare(&1, &2) == :gt))
    |> List.first
  end
end
