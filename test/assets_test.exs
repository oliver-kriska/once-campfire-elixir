defmodule Campfire.AssetsTest do
  use ExUnit.Case, async: false

  setup do
    tmp = Path.join(System.tmp_dir!(), "campfire-assets-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "exported assets include real files and the captured Rails frontend" do
    manifest = Campfire.Assets.read("static/assets/.manifest.json") |> Jason.decode!()

    for {_logical, %{"digested_path" => path}} <- manifest do
      assert File.regular?(Campfire.Assets.file("static/assets/" <> path)), path
    end

    # Captured Rails URLs, not expectations computed from the generated manifest.
    assert Campfire.Assets.path("application.js") == "/assets/application-a54c74a7.js"
    assert Campfire.Assets.path("lexxy.js") == "/assets/lexxy-a21f41d4.js"
    assert Campfire.Assets.path("turbo.js") == "/assets/turbo-a1e3a50a.js"

    assert Campfire.Assets.read("static/assets/application-a54c74a7.js") ==
             File.read!("reference/app/javascript/application.js")
  end

  test "missing Docker image is not reported as a revision mismatch", %{tmp: tmp} do
    File.write!(Path.join(tmp, "docker"), "#!/bin/sh\necho 'No such image' >&2\nexit 1\n")
    File.chmod!(Path.join(tmp, "docker"), 0o755)

    {output, status} = export_with_path(tmp)
    assert status == 1
    assert output =~ "Cannot inspect campfire-reference:app"
    assert output =~ "bin/export-assets --local"
    refute output =~ "Reference image revision differs"
  end

  test "an existing image with the wrong revision is still rejected", %{tmp: tmp} do
    File.write!(Path.join(tmp, "docker"), "#!/bin/sh\necho GIT_REVISION=wrong-revision\n")
    File.chmod!(Path.join(tmp, "docker"), 0o755)

    {output, status} = export_with_path(tmp)
    assert status == 1
    assert output =~ "Reference image revision differs from pinned source"
    refute output =~ "Cannot inspect"
  end

  test "a complete export replaces obsolete digests", %{tmp: tmp} do
    restore_assets = back_up_assets(tmp)
    on_exit(restore_assets)
    File.write!("priv/static/assets/obsolete-digest.js", "stale")
    revision = System.cmd("git", ["rev-parse", "HEAD:reference"]) |> elem(0) |> String.trim()

    write_executable(
      Path.join(tmp, "docker"),
      """
      #!/bin/sh
      case "$1" in
        image) echo GIT_REVISION=#{revision} ;;
        create) echo fixture-container ;;
        cp)
          case "$2" in
            *:/rails/public/assets/.)
              printf '{}' > "$3/.manifest.json"
              printf 'fresh' > "$3/current-digest.js"
              ;;
          esac
          ;;
      esac
      """
    )

    {output, status} = export_with_path(tmp)
    assert status == 0, output
    assert File.read!("priv/static/assets/current-digest.js") == "fresh"
    refute File.exists?("priv/static/assets/obsolete-digest.js")
    assert File.stat!("priv/static/assets").mode |> Bitwise.band(0o777) == 0o755
  end

  test "a failed export preserves the previous asset directory", %{tmp: tmp} do
    File.write!("priv/static/assets/keep-on-failure.js", "preserved")
    on_exit(fn -> File.rm("priv/static/assets/keep-on-failure.js") end)
    revision = System.cmd("git", ["rev-parse", "HEAD:reference"]) |> elem(0) |> String.trim()

    write_executable(
      Path.join(tmp, "docker"),
      """
      #!/bin/sh
      case "$1" in
        image) echo GIT_REVISION=#{revision} ;;
        create) echo fixture-container ;;
        cp) exit 1 ;;
      esac
      """
    )

    {_output, status} = export_with_path(tmp)
    assert status == 1
    assert File.read!("priv/static/assets/keep-on-failure.js") == "preserved"
  end

  defp export_with_path(path) do
    System.cmd("sh", ["bin/export-assets"],
      env: [{"PATH", path <> ":" <> System.get_env("PATH", "")}],
      stderr_to_stdout: true
    )
  end

  defp back_up_assets(tmp) do
    backup = Path.join(tmp, "assets-backup")
    File.cp_r!("priv/static/assets", backup)

    fn ->
      File.rm_rf!("priv/static/assets")
      File.cp_r!(backup, "priv/static/assets")
    end
  end

  defp write_executable(path, contents) do
    File.write!(path, contents)
    File.chmod!(path, 0o755)
  end
end
