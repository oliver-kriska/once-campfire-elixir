defmodule Campfire.HtmlParser do
  @moduledoc """
  Native Gumbo HTML parsing pinned to the Rails reference's Nokogiri version.

  Parsing uses a dirty CPU scheduler because HTML input size does not bound
  Gumbo's tree-construction work.
  """
  @on_load :load

  def load do
    :campfire
    |> :code.priv_dir()
    |> Path.join("native/campfire_html")
    |> String.to_charlist()
    |> :erlang.load_nif(0)
  end

  def parse(html) do
    case parse_dirty(html) do
      {:error, "Document node limit exceeded"} -> parse_isolated(html)
      {:error, message} -> raise ArgumentError, message
      nodes -> nodes
    end
  end

  defp parse_isolated(html) do
    executable = Path.join(:code.priv_dir(:campfire), "native/campfire-html")

    port =
      Port.open({:spawn_executable, String.to_charlist(executable)}, [
        :binary,
        {:packet, 4},
        :exit_status
      ])

    true = Port.command(port, html)

    receive do
      {^port, {:data, data}} ->
        Port.close(port)

        case Jason.decode!(data) do
          %{"error" => message} -> raise ArgumentError, message
          nodes -> Enum.map(nodes, &decode_node/1)
        end

      {^port, {:exit_status, status}} ->
        raise ArgumentError, "isolated HTML parser exited with status #{status}"
    after
      25_000 ->
        Port.close(port)
        raise ArgumentError, "isolated HTML parser timed out"
    end
  end

  defp decode_node([tag, attrs, children]),
    do: {tag, Enum.map(attrs, &List.to_tuple/1), Enum.map(children, &decode_node/1)}

  defp decode_node(%{"comment" => text}), do: {:comment, text}
  defp decode_node(text) when is_binary(text), do: text

  @doc false
  def parse_dirty(_html), do: :erlang.nif_error(:not_loaded)
end
