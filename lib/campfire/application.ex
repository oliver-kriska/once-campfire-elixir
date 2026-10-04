defmodule Campfire.Application do
  use Application

  def start(_, _) do
    database_path = System.get_env("DATABASE_PATH", "var/production.sqlite3")

    children = [
      {Registry, keys: :duplicate, name: Campfire.Streams},
      {Registry, keys: :duplicate, name: Campfire.Connections},
      Campfire.RateLimiter,
      Campfire.FragmentCache,
      Campfire.CableFrames,
      {Campfire.DB, path: database_path},
      {Exqlite,
       name: Campfire.DB.ReadPool,
       database: database_path,
       mode: :readonly,
       pool_size: min(System.schedulers_online(), 8),
       busy_timeout: 5000}
    ]

    children = children ++ Campfire.HtmlParser.children()

    children =
      case System.get_env("REDIS_URL") do
        nil ->
          children

        url ->
          children ++
            [
              {Redix, {url, [name: Campfire.Redis]}}
            ]
      end

    children =
      if System.get_env("CAMPFIRE_WORKER") == "1",
        do: children ++ [Campfire.Worker],
        else: children

    children =
      if System.get_env("CAMPFIRE_NO_SERVER") == "1",
        do: children,
        else:
          children ++
            [
              {Bandit,
               plug: Campfire.Endpoint,
               http_options: [compress: false],
               port: String.to_integer(System.get_env("PORT", "7070")),
               ip:
                 if(System.get_env("CAMPFIRE_BIND") == "loopback",
                   do: {127, 0, 0, 1},
                   else: {0, 0, 0, 0}
                 )}
            ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Campfire.Supervisor)
  end
end
