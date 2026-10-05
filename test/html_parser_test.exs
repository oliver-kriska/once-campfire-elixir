defmodule Campfire.HtmlParserTest do
  use ExUnit.Case, async: false

  test "parser produces native terms through an isolated worker" do
    html = ~s(<p class="message">Hello<!-- pause --><strong>world</strong></p>)

    expected = [
      {"p", [{"class", "message"}], ["Hello", {:comment, " pause "}, {"strong", [], ["world"]}]}
    ]

    assert Campfire.HtmlParser.parse(html) == expected
  end

  test "large fragments use the public parser path without changing output" do
    text = String.duplicate("abcdefgh", 2_049)
    assert [{"p", [], [^text]}] = Campfire.HtmlParser.parse("<p>#{text}</p>")
  end

  test "valid documents beyond the NIF node budget retain Rails behavior" do
    html = String.duplicate("<p>x</p>", 6_000)

    assert nodes = Campfire.HtmlParser.parse(html)
    assert length(nodes) == 6_000
    assert Enum.all?(nodes, &(&1 == {"p", [], ["x"]}))
  end

  test "pathological expansion is isolated from the BEAM" do
    formatting = Enum.map_join(1..390, &~s(<b a="#{&1}">))
    html = "<p>#{formatting}" <> String.duplicate("<p>x", 3_000)

    assert_raise ArgumentError, ~r/isolated HTML parser exited with status/, fn ->
      Campfire.HtmlParser.parse(html)
    end

    assert Campfire.HtmlParser.parse("<p>alive</p>") == [{"p", [], ["alive"]}]
  end

  test "an idle helper death is replaced without crashing its worker or caller" do
    worker = String.to_existing_atom("Elixir.Campfire.HtmlParser.#{:erlang.phash2(self(), 4)}")
    worker_pid = Process.whereis(worker)
    port = :sys.get_state(worker)
    {:os_pid, os_pid} = Port.info(port, :os_pid)

    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
    replacement = await_replacement(worker, port, System.monotonic_time(:millisecond) + 5_000)

    assert is_port(replacement)
    assert Port.info(replacement)
    assert Process.whereis(worker) == worker_pid
    assert Campfire.HtmlParser.parse("<p>alive</p>") == [{"p", [], ["alive"]}]
  end

  test "a helper is recycled after returning a large result" do
    worker = String.to_existing_atom("Elixir.Campfire.HtmlParser.#{:erlang.phash2(self(), 4)}")
    port = :sys.get_state(worker)
    html = String.duplicate("<p>x</p>", 70_000)

    assert nodes = Campfire.HtmlParser.parse(html)
    assert length(nodes) == 70_000
    refute :sys.get_state(worker) == port
    assert Campfire.HtmlParser.parse("<p>alive</p>") == [{"p", [], ["alive"]}]
  end

  defp await_replacement(worker, old_port, deadline) do
    case :sys.get_state(worker) do
      ^old_port ->
        if System.monotonic_time(:millisecond) < deadline do
          await_replacement(worker, old_port, deadline)
        else
          flunk("parser helper was not replaced")
        end

      replacement ->
        replacement
    end
  end
end
