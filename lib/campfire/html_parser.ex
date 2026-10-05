defmodule Campfire.HtmlParser do
  @moduledoc "Bounded, fault-isolated Gumbo parsers pinned to the Rails reference's Nokogiri version."
  use GenServer
  @workers 4

  def children do
    for index <- 0..(@workers - 1) do
      %{id: {__MODULE__, index}, start: {__MODULE__, :start_link, [index]}}
    end
  end

  def start_link(index), do: GenServer.start_link(__MODULE__, index, name: name(index))

  def parse(html) do
    index = :erlang.phash2(self(), @workers)

    case GenServer.call(name(index), {:parse, html}, 30_000) do
      {:error, message} -> raise ArgumentError, message
      %{"error" => message} -> raise ArgumentError, message
      nodes -> Enum.map(nodes, &decode_node/1)
    end
  end

  @impl true
  def init(_index), do: {:ok, open_port()}

  @impl true
  def handle_call({:parse, html}, _from, port) do
    true = Port.command(port, html)

    receive do
      {^port, {:data, data}} ->
        {:reply, Jason.decode!(data), port}

      {^port, {:exit_status, status}} ->
        message = "isolated HTML parser exited with status #{status}"
        {:reply, {:error, message}, open_port()}
    after
      27_000 ->
        Port.close(port)
        {:reply, {:error, "isolated HTML parser timed out"}, open_port()}
    end
  end

  @impl true
  def terminate(_, port) do
    if Port.info(port), do: Port.close(port)
  end

  defp open_port do
    executable = Path.join(:code.priv_dir(:campfire), "native/campfire-html")

    Port.open({:spawn_executable, String.to_charlist(executable)}, [
      :binary,
      {:packet, 4},
      :exit_status
    ])
  end

  defp name(index), do: String.to_atom("Elixir.Campfire.HtmlParser.#{index}")

  defp decode_node([tag, attrs, children]),
    do: {tag, Enum.map(attrs, &List.to_tuple/1), Enum.map(children, &decode_node/1)}

  defp decode_node(%{"comment" => text}), do: {:comment, text}
  defp decode_node(text) when is_binary(text), do: text
end
