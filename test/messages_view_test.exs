defmodule Campfire.MessagesViewTest do
  use ExUnit.Case, async: false
  alias Campfire.{DB, FragmentCache, MessagesView}
  @fixture Jason.decode!(File.read!("test/fixtures/seed.json"))

  setup do
    :ok = DB.restore_fixture(@fixture)
    :ets.delete_all_objects(FragmentCache)
    message = DB.one("SELECT * FROM messages ORDER BY id LIMIT 1")
    %{message: message}
  end

  test "cached fragments receive the current session's CSRF token", %{message: message} do
    first = MessagesView.render(message, "https://campfire.test", "first-session-token")
    second = MessagesView.render(message, "https://campfire.test", "second-session-token")

    assert first =~ ~s(value="first-session-token")
    refute first =~ "second-session-token"
    assert second =~ ~s(value="second-session-token")
    refute second =~ "first-session-token"
  end

  test "broadcast fragments omit CSRF inputs", %{message: message} do
    html = MessagesView.render(message, "https://campfire.test")

    refute html =~ "campfire-csrf-input"
    refute html =~ ~s(name="authenticity_token")
  end
end
