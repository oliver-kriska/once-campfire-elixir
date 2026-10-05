defmodule Campfire.HtmlParserTest do
  use ExUnit.Case, async: true

  test "parser produces native terms on a dirty scheduler" do
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
end
