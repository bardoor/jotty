defmodule Jotty.EscriptRuntime do
  @moduledoc false

  @spec start_application() :: :ok
  def start_application do
    prepare_embedded_priv()

    case Application.ensure_all_started(:jotty) do
      {:ok, _applications} -> :ok
      {:error, reason} -> raise "could not start Jotty: #{inspect(reason)}"
    end
  end

  defp prepare_embedded_priv do
    script = Path.expand(to_string(:escript.script_name()))

    if File.regular?(script) do
      root = extraction_directory(script)
      extract_priv(script, root)
      load_exqlite_from(root)
      Application.put_env(:jotty, :migrations_path, Path.join(root, "jotty/priv/repo/migrations"))
    end
  end

  defp extraction_directory(script) do
    contents = File.read!(script)
    hash = :crypto.hash(:sha256, contents)
    digest = Base.encode16(hash, case: :lower)

    Path.join([System.user_home!(), ".jotty", "runtime", digest])
  end

  defp extract_priv(script, root) do
    {:ok, sections} = :escript.extract(String.to_charlist(script), [])
    {:archive, archive} = List.last(sections)
    {:ok, files} = :zip.extract(archive, ~w(memory)a)

    Enum.each(files, fn {archive_path, contents} ->
      path = to_string(archive_path)

      if extract?(path) do
        destination = Path.join(root, path)
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, contents)
      end
    end)
  end

  defp extract?("exqlite/ebin/exqlite.app"), do: true
  defp extract?("exqlite/priv/" <> _path), do: true
  defp extract?("jotty/priv/" <> _path), do: true
  defp extract?(_path), do: false

  defp load_exqlite_from(root) do
    path = Path.join(root, "exqlite/ebin")
    :code.add_patha(String.to_charlist(path))

    case Application.unload(:exqlite) do
      :ok -> :ok
      {:error, {:not_loaded, :exqlite}} -> :ok
    end

    :ok = Application.load(:exqlite)
  end
end
