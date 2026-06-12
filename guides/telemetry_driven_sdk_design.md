# Telemetry-Driven SDK Design

ExAzure designs telemetry alongside public APIs. This guide covers philosophy, events, and production patterns.

## Why Telemetry-First?

`:telemetry` is the BEAM observability bus. Libraries emit; applications attach handlers.

- No logging framework dependency
- Add metrics without library upgrades
- LiveDashboard, OTel bridges, tests all work

Official Azure SDKs have optional OTel; ExAzure emits events with zero config.

## Two Event Levels

**Operations** — what the user called (once per API call):

```elixir
Telemetry.emit_operation(:blob, :put, %{container: c, name: n})
# => [:ex_azure, :blob, :put]
```

**Requests** — what the pipeline executed (includes retries):

```elixir
Telemetry.span(metadata, fn -> execute_with_retry(...) end)
# => [:ex_azure, :request] with %{duration: native}
```

## Event Reference

| Event | When | Metadata |
|-------|------|----------|
| `[:ex_azure, :blob, :put]` | upload, upload_stream | `container`, `name` |
| `[:ex_azure, :blob, :get]` | download | `container`, `name` |
| `[:ex_azure, :blob, :delete]` | delete | `container`, `name` |
| `[:ex_azure, :blob, :metadata]` | metadata | `container`, `name` |
| `[:ex_azure, :blob, :set_metadata]` | set_metadata | `container`, `name` |
| `[:ex_azure, :container, :*]` | create/delete/list/... | `name` or `container` |
| `[:ex_azure, :request]` | pipeline span | `service`, `operation`, `method`, `path` |
| `[:ex_azure, :auth, :sign]` | SharedKey signing | `scheme`, `account` |
| `[:ex_azure, :retry]` | backoff | `attempt`, `delay_ms` |

## Handler Examples

```elixir
# Dev logging
:telemetry.attach("dev", [:ex_azure, :request], fn _, %{duration: d}, m, _ ->
  ms = System.convert_time_unit(d, :native, :millisecond)
  IO.puts("#{m.service}.#{m.operation} #{ms}ms")
end, nil)

# Test assertion
:telemetry_test.attach_event_handlers(self(), [[:ex_azure, :blob, :put]])
```

## Rules for New Events

1. Name mirrors module: `[:ex_azure, :queue, :send]`
2. Measurements numeric: `count`, `duration`, `delay_ms`
3. Metadata contextual, never secrets
4. Emit operation event before pipeline call
5. Document in `plans/telemetry-design.md`

## Security

Never in metadata: keys, SAS sigs, tokens, Authorization values, request bodies.

## Duration

Native time units — convert in handlers:

```elixir
System.convert_time_unit(d, :native, :millisecond)
```

## Further Reading

- `plans/telemetry-design.md`
- `livebooks/telemetry.livemd`
- [Telemetry hexdocs](https://hexdocs.pm/telemetry/)
