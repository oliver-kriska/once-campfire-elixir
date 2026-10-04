defmodule Campfire.DBTest do
  use ExUnit.Case, async: false
  alias Campfire.DB
  @fixture Jason.decode!(File.read!("test/fixtures/seed.json"))

  setup do
    :ok = DB.restore_fixture(@fixture)
  end

  test "reads use the pool while the writer is busy" do
    parent = self()

    writer =
      Task.async(fn ->
        DB.transaction(fn query ->
          query.("SELECT id FROM accounts LIMIT 1", [])
          send(parent, :writer_started)

          receive do
            :release_writer -> :ok
          end
        end)
      end)

    assert_receive :writer_started

    reader = Task.async(fn -> DB.one("SELECT id FROM accounts LIMIT 1") end)
    assert {:ok, %{"id" => _}} = Task.yield(reader, 1_000)

    send(Process.whereis(DB), :release_writer)
    assert :ok = Task.await(writer)
  end

  test "expected SQLite errors are returned without crashing the writer" do
    assert {:error, %DB.Error{}} = DB.query("SELECT * FROM missing_table")
    assert {:error, %DB.Error{}} = DB.one("SELECT * FROM missing_table")
    assert %{"count" => _} = DB.one("SELECT COUNT(*) AS count FROM messages")
  end

  test "unexpected transaction exceptions crash and restart the writer" do
    writer = Process.whereis(DB)

    {caller, reference} =
      spawn_monitor(fn ->
        DB.transaction(fn _query -> raise "unexpected callback failure" end)
      end)

    assert_receive {:DOWN, ^reference, :process, ^caller, _reason}
    assert eventually(fn -> is_pid(Process.whereis(DB)) && Process.whereis(DB) != writer end)
    assert %{"count" => _} = DB.one("SELECT COUNT(*) AS count FROM messages")
  end

  defp eventually(fun, attempts \\ 50)

  defp eventually(fun, attempts) when attempts > 0,
    do: fun.() || (Process.sleep(20) && eventually(fun, attempts - 1))

  defp eventually(_fun, 0), do: false
end
