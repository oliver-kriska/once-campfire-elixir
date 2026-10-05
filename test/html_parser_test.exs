defmodule Campfire.HtmlParserTest do
  use ExUnit.Case, async: true

  test "normal and dirty scheduler parsers produce the same native terms" do
    html = ~s(<p class="message">Hello<!-- pause --><strong>world</strong></p>)

    expected = [
      {"p", [{"class", "message"}], ["Hello", {:comment, " pause "}, {"strong", [], ["world"]}]}
    ]

    assert Campfire.HtmlParser.parse_nif(html) == expected
    assert Campfire.HtmlParser.parse_dirty(html) == expected
  end

  test "large fragments use the public dirty-scheduler path without changing output" do
    text = String.duplicate("abcdefgh", 2_049)
    assert [{"p", [], [^text]}] = Campfire.HtmlParser.parse("<p>#{text}</p>")
  end
end
