defmodule Campfire.HtmlParser do
  @moduledoc """
  Native Gumbo HTML parsing pinned to the Rails reference's Nokogiri version.

  Small fragments execute directly and larger documents use a dirty CPU
  scheduler so parsing cannot monopolize a normal scheduler.
  """
  @on_load :load
  @dirty_bytes 16_384

  def load do
    :campfire
    |> :code.priv_dir()
    |> Path.join("native/campfire_html")
    |> String.to_charlist()
    |> :erlang.load_nif(0)
  end

  def parse(html) do
    nodes = if byte_size(html) > @dirty_bytes, do: parse_dirty(html), else: parse_nif(html)

    case nodes do
      {:error, message} -> raise ArgumentError, message
      nodes -> nodes
    end
  end

  @doc false
  def parse_nif(_html), do: :erlang.nif_error(:not_loaded)

  @doc false
  def parse_dirty(_html), do: :erlang.nif_error(:not_loaded)
end
