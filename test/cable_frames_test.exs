defmodule Campfire.CableFramesTest do
  use ExUnit.Case, async: false
  alias Campfire.{Cable, CableFrames}

  test "frames preserve Rails escaping and change with payload and identifier" do
    for payload <- [~s({"body":"<p>& café</p>"}), ~s({"body":"updated"})],
        identifier <- ["room-one", "room-two"] do
      expected =
        Campfire.Rails.json(%{"identifier" => identifier, "message" => Jason.decode!(payload)})

      assert {:ok, ^expected} = CableFrames.frame("test", identifier, payload)
      assert {:ok, ^expected} = CableFrames.frame("test", identifier, payload)
    end

    assert {:error, _} = CableFrames.frame("test", "room-one", "invalid")
  end

  test "simultaneous fanout shares one frame and cache remains bounded" do
    payload = ~s({"body":"shared"})

    frames =
      1..100
      |> Task.async_stream(fn _ -> CableFrames.frame("fanout", "id", payload) end)
      |> Enum.to_list()

    assert frames |> Enum.uniq() |> length() == 1
    for i <- 1..4200, do: CableFrames.frame("bounded", Integer.to_string(i), payload)
    assert :ets.info(CableFrames, :size) <= 4096
    assert {:ok, _} = CableFrames.frame("fanout", "id", payload)
  end

  test "interleaved broadcasts retain independent frames for slow subscribers" do
    for i <- 1..100 do
      assert {:ok, _} =
               CableFrames.frame("interleaved", "same-id", Jason.encode!(%{"sequence" => i}))
    end

    for i <- 100..1//-1 do
      payload = Jason.encode!(%{"sequence" => i})
      key = {"interleaved", "same-id", payload}
      assert [{^key, frame}] = :ets.lookup(CableFrames, key)
      assert {:ok, ^frame} = CableFrames.frame("interleaved", "same-id", payload)
    end
  end

  test "local broadcasts share encoded frames without Redis" do
    Registry.register(Campfire.Streams, "room-stream", "subscription-id")

    assert :ok = Cable.broadcast("room-stream", %{"body" => "hello"})

    assert_receive {:delivery, "room-stream", "subscription-id", payload}

    assert {:push, {:text, frame}, %{}} =
             Cable.handle_info({:delivery, "room-stream", "subscription-id", payload}, %{})

    assert Jason.decode!(frame) == %{
             "identifier" => "subscription-id",
             "message" => %{"body" => "hello"}
           }
  end
end
