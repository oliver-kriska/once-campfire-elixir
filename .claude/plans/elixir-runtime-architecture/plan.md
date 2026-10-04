# Elixir runtime architecture fixes

## Scope

Improve only the Elixir implementation at `b6b82e5`. Preserve the SQLite application
schema, storage compatibility, HTTP/frontend behavior, cookies, and Action Cable wire
protocol. Redis compatibility is not itself a requirement.

## Review findings driving this plan

- Message fragment cache keys omit the session-specific CSRF token rendered into the
  cached HTML, allowing one session's token to be served to another session.
- Production Redis is started with snapshots and AOF disabled, so accepted post-commit
  jobs can disappear on restart. Queue errors can also occur after the domain write has
  committed.
- Redis is unnecessarily on every cached-message request and every realtime broadcast,
  despite local ETS/Registry fallback paths and a single-node deployment model.
- Every SQLite read and write is serialized through one `Campfire.DB` GenServer even
  though WAL supports concurrent readers. Existing profiling establishes the high call
  volume, but not that DB serialization is the dominant CPU cost.
- Redis command errors make login throttling fail open.
- `Campfire.DB.transaction/1` converts unexpected programming exceptions into ordinary
  error tuples and loses their stacktraces.
- The webhook test gives `Task.await/1` no headroom over its inner 5-second socket timeout.

## Architecture decisions

- Keep one low-level Exqlite writer process for writes and transactions.
- Add a supervised, read-only Exqlite/DBConnection pool and route only explicit `SELECT`
  statements to it. Transaction callbacks continue using the writer connection.
- Use process-local Registry for Cable fanout and ETS for fragment caching. This matches
  the packaged single application node; a future multi-node deployment would require a
  deliberate distributed PubSub design.
- Retain Redis only for the cross-process job queue in this pass, persist it under the
  existing storage volume, and document that a transactional SQLite outbox is the next
  step if atomic domain-write/job-enqueue semantics are required without Redis.

## Tasks

- [x] Make message fragment caching CSRF-session-safe and add a cross-session regression test.
- [x] Replace Redis fragment cache and Cable PubSub hot paths with local ETS/Registry behavior.
- [x] Make login throttling local and fail closed without depending on Redis availability.
- [x] Persist the packaged Redis job queue and cover its production startup configuration.
- [x] Add a supervised read-only SQLite pool while retaining the serialized writer; test that reads proceed during a blocked writer transaction.
- [x] Preserve expected SQLite errors as tuples while re-raising unexpected transaction callback exceptions with stacktraces.
- [x] Give the webhook task timeout deterministic headroom.
- [x] Update Elixir architecture and benchmark caveats without changing other implementations.
- [x] Run format, warnings-as-errors compile, focused tests, and the full Elixir test suite.
- [ ] Perform a read-only changed-code review and address accepted findings.

## Verification

```sh
bin/mix format --check-formatted
bin/mix compile --warnings-as-errors
bin/mix test --warnings-as-errors
```

If Docker remains unavailable in the orb, use committed verification evidence only for
the unchanged baseline and report new-change verification as blocked rather than green.

## Risks

- Read connections must never receive writes or transaction-local reads.
- Cached fragments must not expose or reuse another session's CSRF token.
- Local Registry fanout intentionally supports one application node; deployment docs must
  not imply multi-node fanout.
- Redis AOF durability reduces but does not eliminate the post-commit enqueue gap.
