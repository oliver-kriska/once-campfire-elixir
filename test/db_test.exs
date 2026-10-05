defmodule Campfire.DBTest do
  use ExUnit.Case, async: false
  alias Campfire.DB
  @fixture Jason.decode!(File.read!("test/fixtures/seed.json"))

  setup do
    :ok = DB.restore_fixture(@fixture)
  end

  test "reads use the pool while the writer is busy" do
    if Process.whereis(DB.ReadPool) do
      parent = self()

      writer =
        Task.async(fn ->
          DB.transaction(fn query ->
            query.("SELECT id FROM accounts LIMIT 1", [])
            send(parent, :writer_started)

            receive do
              :release_writer -> :ok
            after
              5_000 -> raise "writer was not released"
            end
          end)
        end)

      on_exit(fn ->
        if Process.alive?(writer.pid) do
          if pid = Process.whereis(DB), do: send(pid, :release_writer)
        end
      end)

      assert_receive :writer_started

      reader = Task.async(fn -> DB.one("SELECT id FROM accounts LIMIT 1") end)
      assert {:ok, %{"id" => _}} = Task.yield(reader, 1_000)

      send(Process.whereis(DB), :release_writer)
      assert :ok = Task.await(writer)
    else
      assert System.schedulers_online() == 1
    end
  end

  test "expected SQLite errors are returned without crashing the writer" do
    assert {:error, %DB.Error{}} = DB.query("SELECT * FROM missing_table")
    assert {:error, %DB.Error{}} = DB.one("SELECT * FROM missing_table")
    assert %{"count" => _} = DB.one("SELECT COUNT(*) AS count FROM messages")
  end

  test "transactions read their own writes through the public query API" do
    %{"id" => account_id} = DB.one("SELECT id FROM accounts LIMIT 1")

    assert :ok =
             DB.transaction(fn query ->
               query.("UPDATE accounts SET name=? WHERE id=?", [
                 "Updated in transaction",
                 account_id
               ])

               assert DB.one("SELECT name FROM accounts WHERE id=?", [account_id])["name"] ==
                        "Updated in transaction"

               :ok
             end)
  end

  test "unexpected transaction exceptions are reraised in the caller" do
    writer = Process.whereis(DB)

    assert_raise RuntimeError, "unexpected callback failure", fn ->
      DB.transaction(fn _query -> raise "unexpected callback failure" end)
    end

    assert Process.whereis(DB) == writer
    assert %{"count" => _} = DB.one("SELECT COUNT(*) AS count FROM messages")
  end

  test "transaction throws are returned to the caller without killing the writer" do
    writer = Process.whereis(DB)

    assert catch_throw(DB.transaction(fn _query -> throw(:unexpected_callback_throw) end)) ==
             :unexpected_callback_throw

    assert Process.whereis(DB) == writer
    assert %{"count" => _} = DB.one("SELECT COUNT(*) AS count FROM messages")
  end
end
